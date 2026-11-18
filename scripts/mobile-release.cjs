'use strict';

const cp = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const HEX = /^[a-f0-9]+$/i;

function parseReleaseTag(tag) {
  const match = /^v(\d+\.\d+\.\d+)\+([1-9]\d*)$/.exec(String(tag || ''));
  if (!match) return null;
  return { tag, version_name: match[1], version_code: Number(match[2]) };
}

function requireDigest(value, label) {
  if (typeof value !== 'string' || !HEX.test(value) || value.length !== 64) {
    throw new Error(`${label} must be a SHA-256 digest`);
  }
  return value.toLowerCase();
}

function validateBuildRun(run, repository, mode = 'automatic') {
  if (!run || run.status !== 'completed' || run.conclusion !== 'success' ||
      run.path !== '.github/workflows/build-mobile.yml' ||
      run.head_branch !== 'main' || run.head_repository?.full_name !== repository ||
      !/^[a-f0-9]{40}$/i.test(run.head_sha || '') || !/^[1-9]\d*$/.test(String(run.id || ''))) {
    throw new Error('Build run is not a successful same-repository main candidate');
  }
  const allowedEvents = mode === 'manual' ? ['push', 'workflow_dispatch'] : ['push'];
  if (!allowedEvents.includes(run.event)) throw new Error('Build run event is not eligible for publication');
  if (!Number.isSafeInteger(run.run_number) || run.run_number < 1) throw new Error('Build run number is invalid');
  return {
    run_id: String(run.id),
    run_number: run.run_number,
    commit: run.head_sha.toLowerCase(),
    ios_artifact: `Tabby-ios-sideload-${run.run_number}`,
  };
}

async function selectBuildRun({ github, context, env, root = process.cwd() }) {
  const repository = `${context.repo.owner}/${context.repo.repo}`;
  let run;
  let mode = 'automatic';
  if (env.MANUAL_RUN_ID) {
    mode = 'manual';
    if (!/^[1-9]\d*$/.test(env.MANUAL_RUN_ID)) throw new Error('Manual recovery run ID is invalid');
    const response = await github.rest.actions.getWorkflowRun({ ...context.repo, run_id: Number(env.MANUAL_RUN_ID) });
    run = response.data;
    if (env.MANUAL_CANDIDATE_COMMIT && run.head_sha.toLowerCase() !== env.MANUAL_CANDIDATE_COMMIT.toLowerCase()) {
      throw new Error('Manual recovery commit does not match the successful build run');
    }
  } else {
    if (context.eventName === 'workflow_run') {
      if (!/^[1-9]\d*$/.test(env.TRIGGER_RUN_ID || '')) throw new Error('Triggered build run ID is invalid');
      const triggered = (await github.rest.actions.getWorkflowRun({ ...context.repo, run_id: Number(env.TRIGGER_RUN_ID) })).data;
      validateBuildRun(triggered, repository, 'automatic');
    }
    const query = {
      ...context.repo, workflow_id: 'build-mobile.yml', branch: 'main', status: 'success', per_page: 100,
    };
    const candidates = typeof github.paginate === 'function'
      ? await github.paginate(github.rest.actions.listWorkflowRuns, query)
      : (await github.rest.actions.listWorkflowRuns(query)).data.workflow_runs || [];
    candidates.sort((left, right) => (right.run_number || 0) - (left.run_number || 0));
    run = candidates.find((candidate) => {
      try {
        validateBuildRun(candidate, repository, 'automatic');
        return fs.statSync(path.join(root, 'docs', 'releases', `${candidate.head_sha.toLowerCase()}.json`)).isFile();
      } catch (_) { return false; }
    });
    if (!run) return null;
  }

  const selected = validateBuildRun(run, repository, mode);
  try {
    if (!fs.statSync(path.join(root, 'docs', 'releases', `${selected.commit}.json`)).isFile()) return null;
  } catch (_) {
    return null;
  }
  if (env.EXPECTED_RUN_ID && selected.run_id !== env.EXPECTED_RUN_ID) {
    throw new Error('A newer successful main build replaced the candidate while release approval was pending');
  }
  if (env.EXPECTED_CANDIDATE_COMMIT && selected.commit !== env.EXPECTED_CANDIDATE_COMMIT.toLowerCase()) {
    throw new Error('The candidate commit changed while release approval was pending');
  }
  return selected;
}

function verifyTagTarget(root, tag, commit) {
  const found = cp.execFileSync('git', ['tag', '--list', tag], { cwd: root, encoding: 'utf8' }).trim();
  if (!found) return null;
  const target = cp.execFileSync('git', ['rev-parse', '--verify', `refs/tags/${tag}^{commit}`], {
    cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  }).trim().toLowerCase();
  if (target !== commit.toLowerCase()) throw new Error('Existing release tag points to a different commit');
  return target;
}

function validatePairedCandidates(android, ios) {
  const androidCommit = String(android?.commit || '').toLowerCase();
  const iosCommit = String(ios?.source_commit || '').toLowerCase();
  if (!/^[a-f0-9]{40}$/.test(androidCommit) || androidCommit !== iosCommit) {
    throw new Error('Android and iOS artifacts must come from the exact same source commit');
  }
  requireDigest(android.apk_sha256, 'Android APK digest');
  requireDigest(android.certificate_sha256, 'Android signing certificate digest');
  requireDigest(ios.ipa_sha256, 'iOS IPA digest');
  if (android.application_id !== 'com.zalweb.tabby' || android.debuggable !== false ||
      android.zip_16kb_aligned !== true || !Array.isArray(android.native_libraries) ||
      !android.native_libraries.some((item) => item.name?.startsWith('lib/arm64-v8a/'))) {
    throw new Error('Android artifact manifest is not a verified production APK');
  }
  if (ios.package_identifier !== 'com.zalweb.tabby' || ios.bundle_id !== 'com.zalweb.tabby' ||
      ios.version_name !== android.version_name || String(ios.build_number) !== String(android.version_code) ||
      String(ios.version_code) !== String(android.version_code) || ios.unsigned !== true ||
      !Array.isArray(ios.architectures) || !ios.architectures.includes('arm64') ||
      ios.ipa !== 'Tabby.ipa' || typeof ios.simulator_native_smoke !== 'object' ||
      ios.simulator_native_smoke?.outcome !== 'passed') {
    throw new Error('iOS artifact packaging, version, architecture or unsigned report is incomplete');
  }
  if (!/^\d+\.\d+\.\d+$/.test(android.version_name) || !Number.isSafeInteger(android.version_code) || android.version_code < 1) {
    throw new Error('Shared release version is invalid');
  }
  return {
    commit: androidCommit,
    version_name: android.version_name,
    version_code: android.version_code,
    tag: `v${android.version_name}+${android.version_code}`,
    apk_sha256: android.apk_sha256.toLowerCase(),
    ipa_sha256: ios.ipa_sha256.toLowerCase(),
  };
}

function assetDigest(release, name) {
  const matches = (release.assets || []).filter((asset) => asset.name === name);
  if (matches.length !== 1 || matches[0].state !== 'uploaded' || !/^sha256:[a-f0-9]{64}$/i.test(matches[0].digest || '')) return null;
  return matches[0].digest.slice('sha256:'.length).toLowerCase();
}

function planRelease(candidate, releases, latest, tagTarget = null) {
  const candidateTag = parseReleaseTag(candidate.tag);
  if (!candidateTag || candidateTag.version_name !== candidate.version_name || candidateTag.version_code !== candidate.version_code) {
    throw new Error('Release tag does not match the validated shared version');
  }
  requireDigest(candidate.apk_sha256, 'Android APK digest');
  requireDigest(candidate.ipa_sha256, 'iOS IPA digest');

  const latestVersion = latest ? parseReleaseTag(latest.tag_name) : null;
  if (latest && !latestVersion) throw new Error('Latest published release uses an unknown version tag; refusing to publish');
  const existing = (releases || []).find((release) => release.tag_name === candidate.tag);
  const newerPublished = (releases || []).some((release) => {
    if (release.draft || release.prerelease) return false;
    const version = parseReleaseTag(release.tag_name);
    if (!version) return release.id === latest?.id;
    return version.version_code > candidate.version_code;
  });
  if (newerPublished || latestVersion?.version_code > candidate.version_code) {
    return { action: 'skip-stale', tag: candidate.tag };
  }

  if (existing) {
    if (existing.draft) {
      if (tagTarget !== candidate.commit && existing.target_commitish?.toLowerCase() !== candidate.commit) {
        throw new Error('Existing release draft targets a different source commit');
      }
      return { action: 'resume-draft', tag: candidate.tag, release_id: existing.id };
    }
    if (existing.prerelease) throw new Error('Candidate tag already exists as a prerelease');
    if (assetDigest(existing, 'Tabby.apk') !== candidate.apk_sha256 ||
        assetDigest(existing, 'Tabby.ipa') !== candidate.ipa_sha256) {
      throw new Error('Published candidate tag already exists with different or unverifiable platform assets');
    }
    return latest?.id === existing.id
      ? { action: 'noop', tag: candidate.tag, release_id: existing.id }
      : { action: 'promote-existing', tag: candidate.tag, release_id: existing.id };
  }

  if (latestVersion && latestVersion.version_code >= candidate.version_code) {
    return { action: 'skip-stale', tag: candidate.tag };
  }
  return { action: 'create', tag: candidate.tag };
}

module.exports = { assetDigest, parseReleaseTag, planRelease, selectBuildRun, validateBuildRun, validatePairedCandidates, verifyTagTarget };
