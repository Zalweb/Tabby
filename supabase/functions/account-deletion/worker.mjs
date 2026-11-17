const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);

// The caller is a trusted operator after reviewing this exact user request.
// Every external acknowledgement is followed by a database check. Lost replies
// leave processing resumable and can never turn a request into false completion.
export async function processDeletion({requestId, rpc, ban, remove, softDelete}) {
  if (!uuid(requestId)) throw Error('Invalid request');
  const request = await rpc('review_account_deletion_v1', {p_request_id: requestId});
  if (request.request_id !== requestId || !uuid(request.account_id) ||
      typeof request.auth_deleted !== 'boolean' ||
      !['requested','processing','completed'].includes(request.status)) throw Error('Invalid review');
  if (request.status === 'completed') return {status:'completed'};
  const account = request.account_id;
  if (!request.auth_deleted) await ban(account);
  const prepared = await rpc('prepare_account_deletion_v1', {p_request_id: requestId});
  if (prepared.account_id !== account || !['processing','completed'].includes(prepared.status)) throw Error('Invalid preparation');
  if (prepared.status==='completed') return {status:'completed'};
  // Bound each invocation; another reviewed invocation resumes pending objects.
  for (let batch=0; batch<10; batch++) {
    const objects = await rpc('pending_deletion_objects_v1', {p_request_id:requestId});
    if (!Array.isArray(objects) || objects.length>100) throw Error('Invalid cleanup batch');
    if (!objects.length) {
      if (!request.auth_deleted) await softDelete(account);
      if (await rpc('finish_account_deletion_v1', {p_request_id:requestId}) !== true) throw Error('Completion not acknowledged');
      return {status:'completed'};
    }
    for (const object of objects) {
      if (!['profile-avatars','payment-methods'].includes(object.bucket) ||
          typeof object.path!=='string' || !object.path.startsWith(account+'/') ||
          object.path.split('/').some(part=>!part || part==='.' || part==='..') || /[\u0000-\u001f\\]/.test(object.path)) throw Error('Invalid cleanup scope');
      await remove(object.bucket,object.path);
      if (await rpc('acknowledge_deletion_object_v1', {
        p_request_id:requestId,p_bucket:object.bucket,p_path:object.path}) !== true) throw Error('Removal not confirmed');
    }
  }
  return {status:'processing'};
}

export function makeHandler({secret,serviceKey,process}) {
  return async request => {
    if (request.method!=='POST') return new Response(null,{status:405});
    if (!secret || !serviceKey) return new Response('Worker unavailable',{status:503});
    if (request.headers.get('authorization') !== `Bearer ${serviceKey}` ||
        request.headers.get('x-privacy-review-secret') !== secret) return new Response(null,{status:403});
    try {
      const body = await request.text();
      if (body.length>1024) return new Response(null,{status:400});
      const data=JSON.parse(body);
      if (data.reviewed!==true || !uuid(data.request_id) ||
          Object.keys(data).some(key=>!['reviewed','request_id'].includes(key))) return new Response(null,{status:400});
      return Response.json(await process(data.request_id));
    } catch (_) {
      // Never return provider bodies, account data, paths or credentials.
      return new Response('Processing not completed; retry the reviewed request.',{status:503});
    }
  };
}
