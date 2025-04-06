import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import StorageModule from './NuclearCertificationStorageModule'

const NuclearCertificationImplModule = buildModule('NuclearCertificationImplModule', (m) => {

  const { nuclearCertificationStorage } = m.useModule(StorageModule)

  const nuclearCertificationImpl = m.contract('NuclearCertificationImpl', [
    nuclearCertificationStorage
  ])

  return { nuclearCertificationImpl }
})

export default NuclearCertificationImplModule
