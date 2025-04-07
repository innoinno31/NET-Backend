import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import StorageModule from './NuclearCertificationStorageModule'

const NuclearCertificationImplModule = buildModule('NuclearCertificationImplModule', (m) => {

  const { nuclearCertificationStorage } = m.useModule(StorageModule)

  // 1. Deploy Impl, passing the Storage contract address
  const nuclearCertificationImpl = m.contract('NuclearCertificationImpl', [
    nuclearCertificationStorage
  ])

  // 2. Call setImplementationContract on Storage, passing the Impl address
  m.call(nuclearCertificationStorage, "setImplementationContract", [
    nuclearCertificationImpl
  ])

  return { nuclearCertificationImpl, nuclearCertificationStorage }
})

export default NuclearCertificationImplModule
