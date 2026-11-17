'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { template } = require('./azure-full-template.cjs');
const fixture = () => ({publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureKey', dnsLabel: 'tabby-fixture'});
test('destination permits only HTTPS/ACME publicly and never a database/SSH port', () => {
  const result = template(fixture());
  const nsg = result.resources.find(r => r.type.endsWith('networkSecurityGroups'));
  assert.deepEqual(nsg.properties.securityRules.map(r => r.properties.destinationPortRange), ['80', '443']);
  const vm = result.resources.find(r => r.type.endsWith('virtualMachines'));
  assert.equal(vm.properties.osProfile.linuxConfiguration.disablePasswordAuthentication, true);
  assert.equal(vm.properties.storageProfile.osDisk.deleteOption, 'Detach');
  const init = Buffer.from(vm.properties.osProfile.customData, 'base64').toString();
  assert(!init.includes('SUPABASE_ACCESS_TOKEN='));
  assert(!init.includes('PRIVATE KEY'));
});
test('unreviewed size, disallowed region, injected hostname and private keys fail closed', () => {
  for (const change of [{location: 'southeastasia'}, {vmSize: 'Standard_D96s_v5'}, {dnsLabel: 'x;whoami'}, {publicKey: '-----BEGIN PRIVATE KEY-----'}]) {
    assert.throws(() => template({...fixture(), ...change}));
  }
});
