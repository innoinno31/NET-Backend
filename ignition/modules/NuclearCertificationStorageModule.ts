import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const NuclearCertificationStorageModule = buildModule("NuclearCertificationStorageModule", (m) => {

  const nuclearCertificationStorage = m.contract("NuclearCertificationStorage", []);

  return { nuclearCertificationStorage };
});

export default NuclearCertificationStorageModule;
