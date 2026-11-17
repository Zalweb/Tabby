#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

function template({ publicKey, dnsLabel, location = 'eastasia', vmSize = 'Standard_B2als_v2' }) {
  if (!['eastasia', 'australiaeast', 'koreacentral', 'centralindia', 'malaysiawest'].includes(location)) throw Error('Region is outside the verified subscription policy.');
  if (!/^ssh-ed25519 [A-Za-z0-9+/=]+(?: .*)?$/.test(publicKey.trim())) throw Error('A public Ed25519 SSH key is required; never supply a private key.');
  if (!/^[a-z][a-z0-9-]{2,50}$/.test(dnsLabel)) throw Error('Invalid public DNS label.');
  if (vmSize !== 'Standard_B2als_v2') throw Error('A different VM needs a fresh capacity/cost review.');
  const content = file => fs.readFileSync(path.join(root, 'deploy', 'azure-full', file), 'utf8');
  const hostname = `${dnsLabel}.${location}.cloudapp.azure.com`;
  const cloudInit = '#cloud-config\n' + JSON.stringify({
    package_update: true,
    packages: ['ca-certificates', 'git', 'openssl', 'python3', 'docker.io', 'docker-compose-v2'],
    write_files: [
      {path: '/etc/tabby-hostname', permissions: '0644', content: hostname},
      ...['bootstrap.sh', 'initialize-platform.sh', 'generate-env.py', 'docker-compose.private.yml'].map(file => ({
        path: `/opt/tabby/${file}`, permissions: '0700', encoding: 'b64', content: Buffer.from(content(file)).toString('base64'),
      })),
    ],
    runcmd: [['bash', '/opt/tabby/bootstrap.sh']],
  });
  const id = (type, name) => `[resourceId('${type}','${name}')]`;
  const networkVersion = '2024-05-01';
  const tags = {Project: 'Tabby', Stage: 'migration', TotalCreditLimitUSD: '100'};
  return {
    $schema: 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#',
    contentVersion: '1.0.0.0',
    resources: [
      {type: 'Microsoft.Network/networkSecurityGroups', apiVersion: networkVersion, name: 'tabby-nsg', location, tags,
        properties: {securityRules: [80, 443].map((port, i) => ({name: `public-${port}`, properties: {
          protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: String(port), sourceAddressPrefix: 'Internet',
          destinationAddressPrefix: '*', access: 'Allow', priority: 100 + i, direction: 'Inbound',
        }}))}},
      {type: 'Microsoft.Network/virtualNetworks', apiVersion: networkVersion, name: 'tabby-vnet', location, tags,
        properties: {addressSpace: {addressPrefixes: ['10.26.0.0/16']}, subnets: [{name: 'backend', properties: {addressPrefix: '10.26.1.0/24'}}]}},
      {type: 'Microsoft.Network/publicIPAddresses', apiVersion: networkVersion, name: 'tabby-ip', location, tags,
        sku: {name: 'Standard'}, properties: {publicIPAllocationMethod: 'Static', publicIPAddressVersion: 'IPv4', dnsSettings: {domainNameLabel: dnsLabel}}},
      {type: 'Microsoft.Network/networkInterfaces', apiVersion: networkVersion, name: 'tabby-nic', location, tags,
        dependsOn: [id('Microsoft.Network/networkSecurityGroups', 'tabby-nsg'), id('Microsoft.Network/virtualNetworks', 'tabby-vnet'), id('Microsoft.Network/publicIPAddresses', 'tabby-ip')],
        properties: {networkSecurityGroup: {id: id('Microsoft.Network/networkSecurityGroups', 'tabby-nsg')}, ipConfigurations: [{name: 'primary', properties: {
          privateIPAllocationMethod: 'Dynamic', subnet: {id: "[resourceId('Microsoft.Network/virtualNetworks/subnets','tabby-vnet','backend')]"},
          publicIPAddress: {id: id('Microsoft.Network/publicIPAddresses', 'tabby-ip')},
        }}]}},
      {type: 'Microsoft.Compute/virtualMachines', apiVersion: '2024-07-01', name: 'tabby-supabase', location, tags,
        identity: {type: 'SystemAssigned'}, dependsOn: [id('Microsoft.Network/networkInterfaces', 'tabby-nic')],
        properties: {hardwareProfile: {vmSize}, osProfile: {
          computerName: 'tabby-backend', adminUsername: 'tabbyadmin', customData: Buffer.from(cloudInit).toString('base64'),
          linuxConfiguration: {disablePasswordAuthentication: true, provisionVMAgent: true,
            ssh: {publicKeys: [{path: '/home/tabbyadmin/.ssh/authorized_keys', keyData: publicKey.trim()}]}},
        }, storageProfile: {
          imageReference: {publisher: 'Canonical', offer: 'ubuntu-24_04-lts', sku: 'server', version: 'latest'},
          osDisk: {name: 'tabby-os-data', createOption: 'FromImage', caching: 'ReadWrite', diskSizeGB: 64,
            managedDisk: {storageAccountType: 'StandardSSD_LRS'}, deleteOption: 'Detach'},
        }, networkProfile: {networkInterfaces: [{id: id('Microsoft.Network/networkInterfaces', 'tabby-nic')}]},
        diagnosticsProfile: {bootDiagnostics: {enabled: true}}}},
    ],
    outputs: {apiUrl: {type: 'string', value: `[concat('https://',reference(resourceId('Microsoft.Network/publicIPAddresses','tabby-ip')).dnsSettings.fqdn)]`},
      vmName: {type: 'string', value: 'tabby-supabase'}},
  };
}
module.exports = { template };
if (require.main === module) {
  const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  fs.writeFileSync(process.argv[3], JSON.stringify(template(config), null, 2) + '\n');
  console.log('Prepared Azure migration template. No credentials or production data embedded.');
}
