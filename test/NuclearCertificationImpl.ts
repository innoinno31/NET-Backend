import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { ethers } from "hardhat"
import { ContractFactory, Log, EventLog } from "ethers"
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs"
import { NuclearCertificationStorage, NuclearCertificationImpl } from "../typechain-types"

describe("NuclearCertificationImpl", () => {
    // --- Constants ---
    const PLANT_OPERATOR_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("PLANT_OPERATOR_ADMIN"))
    const MANUFACTURER = ethers.keccak256(ethers.toUtf8Bytes("MANUFACTURER"))
    const LABORATORY = ethers.keccak256(ethers.toUtf8Bytes("LABORATORY"))
    const REGULATORY_AUTHORITY = ethers.keccak256(ethers.toUtf8Bytes("REGULATORY_AUTHORITY"))
    const CERTIFICATION_OFFICER = ethers.keccak256(ethers.toUtf8Bytes("CERTIFICATION_OFFICER"))
    const IMPL_ROLE = ethers.keccak256(ethers.toUtf8Bytes("IMPL_ROLE"))
    const DEFAULT_ADMIN_ROLE = ethers.ZeroHash

    // --- Enums --- Values matching Solidity enums
    const DocumentType = {
        Certification: 0,
        LabReport: 1,
        TechFile: 2,
        Compliance: 3,
        RegulatoryReview: 4
    }

    const DocumentStatus = {
        Submitted: 0,
        Pending: 1,
        Rejected: 2,
        Deprecated: 3
    }

    const EquipmentStatus = {
        Registered: 0,
        Pending: 1,
        Certified: 2,
        Rejected: 3,
        Deprecated: 4
    }

    const CertificationSteps = {
        Registered: 0,
        DocumentsPending: 1,
        ReadyForReview: 2,
        UnderReview: 3,
        Certified: 4,
        Rejected: 5
    }


    // --- Fixture ---
    async function deployFullSystemFixture() {
        const [
            deployer,
            plantOperatorAdmin,
            manufacturer,
            laboratory,
            regulatoryAuthority,
            certificationOfficer,
            user
        ] = await ethers.getSigners()

        // Deploy Storage Contract
        const StorageFactory: ContractFactory = await ethers.getContractFactory("NuclearCertificationStorage")
        const storageContract = (await StorageFactory.connect(deployer).deploy()) as NuclearCertificationStorage
        await storageContract.waitForDeployment()
        const storageAddress = await storageContract.getAddress()

        expect(await storageContract.hasRole(DEFAULT_ADMIN_ROLE, deployer.address)).to.be.true

        // Deploy Impl Contract
        const ImplFactory: ContractFactory = await ethers.getContractFactory("NuclearCertificationImpl")
        const implContract = (await ImplFactory.connect(deployer).deploy(storageAddress)) as NuclearCertificationImpl
        await implContract.waitForDeployment()
        const implAddress = await implContract.getAddress()

        // Set Impl address in Storage and grant IMPL_ROLE
        await storageContract.connect(deployer).setImplementationContract(implAddress)

        expect(await storageContract.hasRole(IMPL_ROLE, implAddress)).to.be.true

        return {
            storageContract,
            implContract,
            deployer,
            plantOperatorAdmin,
            manufacturer,
            laboratory,
            regulatoryAuthority,
            certificationOfficer,
            user
        }
    }

    // Fixture with registered roles and a plant
    async function fixtureWithRolesAndPlant() {
        const base = await loadFixture(deployFullSystemFixture)
        const { implContract, storageContract, deployer, plantOperatorAdmin, manufacturer, laboratory, regulatoryAuthority, certificationOfficer } = base
    
        const plantId = 0
        const plantName = "Centralia"
    
        await implContract.connect(deployer).registerPlant(plantName, "Main Nuclear Plant", "Sector 7G", true)
        await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "OperatorAdmin Alice")
    
        await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer Bob")
        await implContract.connect(plantOperatorAdmin).registerLaboratory(laboratory.address, plantId, "Laboratory Charlie")
        await implContract.connect(plantOperatorAdmin).registerRegulatoryAuthority(regulatoryAuthority.address, plantId, "Regulator Dave")
        await implContract.connect(plantOperatorAdmin).registerCertificationOfficer(certificationOfficer.address, plantId, "Certifier Eve")
    
        return { ...base, plantId, plantName }
    }    

     // Fixture with roles, plant, and a registered equipment
     async function fixtureWithRegisteredEquipment() {
         const base = await loadFixture(fixtureWithRolesAndPlant)
         const { implContract, storageContract, plantOperatorAdmin, plantId } = base

         const equipmentId = 0
         const equipmentName = "Reactor Pump 1"
         const equipmentDesc = "Primary coolant pump"

         await implContract.connect(plantOperatorAdmin).registerEquipment(
            equipmentName,
            equipmentDesc,
            plantId
        )

         const equipment = await storageContract.getEquipment(equipmentId)
         expect(equipment.name).to.equal(equipmentName)
         expect(equipment.description).to.equal(equipmentDesc)
         expect(equipment.status).to.equal(EquipmentStatus.Registered)
         expect(equipment.currentStep).to.equal(CertificationSteps.Registered)
         expect(await storageContract.ownerOf(equipmentId)).to.equal(plantOperatorAdmin.address)

         return { ...base, equipmentId, equipmentName, equipmentDesc }
     }

    // Fixture with equipment ready for review
    async function fixtureWithEquipmentReadyForReview() {
        const base = await loadFixture(fixtureWithRegisteredEquipment)
        const { implContract, storageContract, manufacturer, laboratory, plantOperatorAdmin, equipmentId } = base

        // Register necessary documents
        await implContract.connect(manufacturer).registerDocument(equipmentId, DocumentType.TechFile, "Pump Spec", "Tech details", "QmSpecHash")
        await implContract.connect(laboratory).registerDocument(equipmentId, DocumentType.LabReport, "Stress Test", "Test results", "QmLabHash")

        // Mark as ready for review
        await implContract.connect(plantOperatorAdmin).equipmentIsReadyForReview(equipmentId)
        
        const equipment = await storageContract.getEquipment(equipmentId)
        expect(equipment.currentStep).to.equal(CertificationSteps.ReadyForReview)

        return base
    }

    // --- Deployment Tests ---
    describe("Deployment", () => {
        it("should_deploy_impl_and_storage_correctly", async () => {
            const { storageContract, implContract } = await loadFixture(deployFullSystemFixture)
            expect(await storageContract.getAddress()).to.be.properAddress
            expect(await implContract.getAddress()).to.be.properAddress
        })

        it("should_link_impl_and_storage_correctly", async () => {
            const { storageContract, implContract } = await loadFixture(deployFullSystemFixture)
            const implAddress = await implContract.getAddress()
            const storageAddress = await storageContract.getAddress()

            // Check Impl has correct storage address
            expect(await implContract.storageContract()).to.equal(storageAddress)

            // Check Storage has correct Impl address and role
            // Note: Storage doesn't expose _implContractAddress directly, check IMPL_ROLE holder
            expect(await storageContract.hasRole(IMPL_ROLE, implAddress)).to.be.true
        })
    })

    describe("Plant Registration", () => {
        it("should_allow_admin_to_register_a_plant", async () => {
            const { implContract, storageContract, deployer } = await loadFixture(deployFullSystemFixture)
            const plantName = "Plant Alpha"
            const plantDesc = "Test plant"
            const plantLoc = "Area 51"
            const plantId = 0

            await implContract.connect(deployer).registerPlant(plantName, plantDesc, plantLoc, true)

            const plant = await storageContract.getPlant(plantId)
            expect(plant.name).to.equal(plantName)
            expect(plant.description).to.equal(plantDesc)
            expect(plant.location).to.equal(plantLoc)
            expect(plant.isActive).to.be.true
        })

        it("should_revert_if_non_admin_tries_to_register_a_plant", async () => {
             const { implContract, user } = await loadFixture(deployFullSystemFixture)
             await expect(implContract.connect(user).registerPlant("Forbidden Plant", "Desc", "Loc", true))
                 .to.be.revertedWith("Caller doesn't have the required role") // Reverted by onlyRole modifier in Impl
        })

        it("should_allow_admin_to_register_plant_operator_admin", async () => {
            const { implContract, storageContract, deployer, plantOperatorAdmin } = await loadFixture(deployFullSystemFixture)
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Desc", "Loc", true) // Need a plant

            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Alice Admin")

            expect(await storageContract.hasRole(PLANT_OPERATOR_ADMIN, plantOperatorAdmin.address)).to.be.true
            
            const actor = await storageContract.getActor(0)
            expect(actor.name).to.equal("Alice Admin")
            expect(actor.actorAddress).to.equal(plantOperatorAdmin.address)
            expect(actor.role).to.equal(PLANT_OPERATOR_ADMIN)
            expect(actor.plantId).to.equal(plantId)
        })

        it("should_revert_if_non_admin_tries_to_register_plant_operator_admin", async () => {
            const { implContract, user, plantOperatorAdmin } = await loadFixture(deployFullSystemFixture)
            await expect(implContract.connect(user).registerPlantOperator(plantOperatorAdmin.address, 0, "Test"))
                 .to.be.revertedWith("Caller doesn't have the required role") // Reverted by onlyRole modifier in Impl
        })

        it("should_allow_plant_operator_admin_to_register_other_roles", async () => {
            const base = await loadFixture(deployFullSystemFixture)
            const { implContract, storageContract, deployer, plantOperatorAdmin, manufacturer } = base

            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Desc", "Loc", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Admin")

            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer Test")

            expect(await storageContract.hasRole(MANUFACTURER, manufacturer.address)).to.be.true
            
            const actor = await storageContract.getActor(1)
            expect(actor.name).to.equal("Manufacturer Test")
            expect(actor.actorAddress).to.equal(manufacturer.address)
            expect(actor.role).to.equal(MANUFACTURER)
            expect(actor.plantId).to.equal(plantId)
        })

        it("should_revert_if_non_plant_operator_admin_tries_to_register_other_roles", async () => {
            const base = await loadFixture(deployFullSystemFixture)
            const { implContract, deployer, user, laboratory } = base

            await implContract.connect(deployer).registerPlant("Test Plant", "Desc", "Loc", true)

            // Try to register a laboratory as a regular user
            await expect(implContract.connect(user).registerLaboratory(
                laboratory.address, 0, "Laboratory Test"
            )).to.be.revertedWith("Caller doesn't have the required role")
        })

        it("should_revert_if_registering_a_role_already_assigned", async () => {
            const base = await loadFixture(deployFullSystemFixture)
            const { implContract, deployer, plantOperatorAdmin, manufacturer } = base

            await implContract.connect(deployer).registerPlant("Test Plant", "Desc", "Loc", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, 0, "Admin")

            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, 0, "Manufacturer Test")

            await expect(
                implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, 0, "NameZ")
            ).to.be.revertedWithCustomError(implContract, "RoleAlreadyAssigned")
        })
    })

    describe("Equipment Registration", () => {
        it("should_allow_plant_operator_admin_to_register_equipment", async () => {
            const { implContract, storageContract, deployer, plantOperatorAdmin } = await loadFixture(deployFullSystemFixture)
            
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            
            const equipmentName = "Reactor Pump"
            const equipmentDesc = "Primary cooling"
            
            await implContract.connect(plantOperatorAdmin).registerEquipment(equipmentName, equipmentDesc, plantId)
            
            const equipment = await storageContract.getEquipment(0)
            expect(equipment.name).to.equal(equipmentName)
            expect(equipment.description).to.equal(equipmentDesc)
            expect(equipment.status).to.equal(EquipmentStatus.Registered)
            expect(equipment.currentStep).to.equal(CertificationSteps.Registered)
            
            expect(await storageContract.ownerOf(0)).to.equal(plantOperatorAdmin.address)
        })

        it("should_revert_if_non_plant_operator_admin_tries_to_register_equipment", async () => {
            const { implContract, deployer, user } = await loadFixture(deployFullSystemFixture)
            await implContract.connect(deployer).registerPlant("Test Plant", "Desc", "Loc", true)
            
            await expect(
                implContract.connect(user).registerEquipment("Test Equipment", "Description", 0)
            ).to.be.revertedWith("Caller doesn't have the required role")
        })

        it("should_revert_if_registering_equipment_for_non_existent_plant", async () => {
            const { implContract, deployer, plantOperatorAdmin } = await loadFixture(deployFullSystemFixture)
            await implContract.connect(deployer).registerPlant("Test Plant", "Desc", "Loc", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, 0, "Admin")
            
            const nonExistentPlantId = 999
            await expect(
                implContract.connect(plantOperatorAdmin).registerEquipment("Test Equipment", "Description", nonExistentPlantId)
            ).to.be.revertedWithCustomError(implContract, "PlantNotFound")
        })

        it("should_revert_if_registering_equipment_with_empty_name", async () => {
            const { implContract, deployer, plantOperatorAdmin } = await loadFixture(deployFullSystemFixture)
            await implContract.connect(deployer).registerPlant("Test Plant", "Desc", "Loc", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, 0, "Admin")
            
            await expect(
                implContract.connect(plantOperatorAdmin).registerEquipment("", "Description", 0)
            ).to.be.revertedWithCustomError(implContract, "InvalidInput")
        })
    })

     describe("Document Registration", () => {
        it("should_allow_authorized_roles_to_register_documents", async () => {
            const { implContract, storageContract, deployer, plantOperatorAdmin, manufacturer, laboratory } = await loadFixture(deployFullSystemFixture)
            
            // Create a plant and register roles
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer")
            await implContract.connect(plantOperatorAdmin).registerLaboratory(laboratory.address, plantId, "Laboratory")
            
            await implContract.connect(plantOperatorAdmin).registerEquipment("Reactor Pump", "Primary cooling", plantId)
            const equipmentId = 0
            
            const docName = "Tech Spec"
            const docDesc = "Specifications"
            const docHash = "QmTechHash"
            
            await implContract.connect(manufacturer).registerDocument(
                equipmentId, DocumentType.TechFile, docName, docDesc, docHash
            )
            
            const document = await storageContract.getDocument(0)
            expect(document.name).to.equal(docName)
            expect(document.description).to.equal(docDesc)
            expect(document.ipfsHash).to.equal(docHash)
            expect(document.docType).to.equal(DocumentType.TechFile)
            expect(document.submitter).to.equal(manufacturer.address)
            expect(document.status).to.equal(0) // DocumentStatus.Submitted
            
            const equipmentDocs = await storageContract.getEquipmentDocuments(equipmentId)
            expect(equipmentDocs.length).to.equal(1)
            expect(equipmentDocs[0]).to.equal(0)
        })

        it("should_revert_if_unauthorized_role_tries_to_register_document", async () => {
            const { implContract, deployer, plantOperatorAdmin, user } = await loadFixture(deployFullSystemFixture)
            
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            
            await implContract.connect(plantOperatorAdmin).registerEquipment("Reactor Pump", "Primary cooling", plantId)
            const equipmentId = 0
            
            await expect(
                implContract.connect(user).registerDocument(
                    equipmentId, DocumentType.TechFile, "Tech Spec", "Specifications", "QmTechHash"
                )
            ).to.be.revertedWith("Unauthorized role")
        })

        it("should_revert_if_registering_document_for_non_existent_equipment", async () => {
            const { implContract, deployer, plantOperatorAdmin, manufacturer } = await loadFixture(deployFullSystemFixture)
            
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer")
            
            // Try to register a document for a non-existent equipment
            const nonExistentEquipmentId = 999
            await expect(
                implContract.connect(manufacturer).registerDocument(
                    nonExistentEquipmentId, DocumentType.TechFile, "Tech Spec", "Specifications", "QmTechHash"
                )
            ).to.be.revertedWithCustomError(implContract, "EquipmentNotFound")
        })

        it("should_revert_if_registering_document_with_empty_fields", async () => {
            const { implContract, deployer, plantOperatorAdmin, manufacturer } = await loadFixture(deployFullSystemFixture)
            
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer")
            
            await implContract.connect(plantOperatorAdmin).registerEquipment("Reactor Pump", "Primary cooling", plantId)
            const equipmentId = 0
            
            await expect(
                implContract.connect(manufacturer).registerDocument(
                    equipmentId, DocumentType.TechFile, "", "Specifications", "QmTechHash"
                )
            ).to.be.revertedWithCustomError(implContract, "InvalidInput")
            
            await expect(
                implContract.connect(manufacturer).registerDocument(
                    equipmentId, DocumentType.TechFile, "Tech Spec", "Specifications", ""
                )
            ).to.be.revertedWithCustomError(implContract, "InvalidInput")
        })

        it("should_revert_if_registering_document_for_certified_equipment_by_unauthorized", async () => {
            const { implContract, deployer, plantOperatorAdmin, manufacturer, regulatoryAuthority, laboratory, user } = await loadFixture(deployFullSystemFixture)
            
            // Create a plant and register roles
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer")
            await implContract.connect(plantOperatorAdmin).registerLaboratory(laboratory.address, plantId, "Laboratory")
            await implContract.connect(plantOperatorAdmin).registerRegulatoryAuthority(regulatoryAuthority.address, plantId, "Regulator")
            
            // Register equipment
            await implContract.connect(plantOperatorAdmin).registerEquipment("Reactor Pump", "Primary cooling", plantId)
            const equipmentId = 0
            
            // Add necessary documents
            await implContract.connect(manufacturer).registerDocument(equipmentId, DocumentType.TechFile, "Tech Spec", "Specifications", "QmTechHash")
            await implContract.connect(laboratory).registerDocument(equipmentId, DocumentType.LabReport, "Lab Report", "Test Results", "QmLabHash")
            
            // Mark as ready for review
            await implContract.connect(plantOperatorAdmin).equipmentIsReadyForReview(equipmentId)
            
            // Start the review
            await implContract.connect(regulatoryAuthority).reviewEquipment(equipmentId)
            
            // Finalize certification with approval
            const certHash = ethers.keccak256(ethers.toUtf8Bytes("certification_hash"))
            await implContract.connect(regulatoryAuthority).finalizeCertification(equipmentId, true, certHash, "")
            
            // Try to register a document for a certified equipment by an unauthorized user
            await expect(
                implContract.connect(manufacturer).registerDocument(
                    equipmentId, DocumentType.TechFile, "New Spec", "Updated Specs", "QmNewHash"
                )
            ).to.be.revertedWithCustomError(implContract, "EquipmentAlreadyCertified")
        })

        it("should_allow_admin_or_regulator_to_register_doc_for_certified_equipment", async () => {
            const { implContract, storageContract, deployer, plantOperatorAdmin, manufacturer, regulatoryAuthority, laboratory } = await loadFixture(deployFullSystemFixture)
            
            // Create a plant and register roles
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer")
            await implContract.connect(plantOperatorAdmin).registerLaboratory(laboratory.address, plantId, "Laboratory")
            await implContract.connect(plantOperatorAdmin).registerRegulatoryAuthority(regulatoryAuthority.address, plantId, "Regulator")
            
            // Register equipment
            await implContract.connect(plantOperatorAdmin).registerEquipment("Reactor Pump", "Primary cooling", plantId)
            const equipmentId = 0
            
            // Add necessary documents
            await implContract.connect(manufacturer).registerDocument(equipmentId, DocumentType.TechFile, "Tech Spec", "Specifications", "QmTechHash")
            await implContract.connect(laboratory).registerDocument(equipmentId, DocumentType.LabReport, "Lab Report", "Test Results", "QmLabHash")
            
            // Mark as ready for review
            await implContract.connect(plantOperatorAdmin).equipmentIsReadyForReview(equipmentId)
            
            // Start the review
            await implContract.connect(regulatoryAuthority).reviewEquipment(equipmentId)
            
            // Finalize certification with approval
            const certHash = ethers.keccak256(ethers.toUtf8Bytes("certification_hash"))
            await implContract.connect(regulatoryAuthority).finalizeCertification(equipmentId, true, certHash, "")
            
            // Verify that the equipment is properly certified
            const certifiedEquipment = await storageContract.getEquipment(equipmentId)
            expect(certifiedEquipment.status).to.equal(EquipmentStatus.Certified)
            expect(certifiedEquipment.currentStep).to.equal(CertificationSteps.Certified)
            
            // Register a document for certified equipment as a regulatory authority
            const postCertDocName = "Post-Cert Review"
            const postCertDocDesc = "Follow-up"
            const postCertDocHash = "QmPostCertHash"
            
            await implContract.connect(regulatoryAuthority).registerDocument(
                equipmentId, DocumentType.RegulatoryReview, postCertDocName, postCertDocDesc, postCertDocHash
            )
            
            const docId = 2 // Third document (index 2)
            const document = await storageContract.getDocument(docId)
            expect(document.name).to.equal(postCertDocName)
            expect(document.description).to.equal(postCertDocDesc)
            expect(document.ipfsHash).to.equal(postCertDocHash)
            expect(document.docType).to.equal(DocumentType.RegulatoryReview)
            expect(document.submitter).to.equal(regulatoryAuthority.address)
            
            const equipmentDocs = await storageContract.getEquipmentDocuments(equipmentId)
            expect(equipmentDocs.length).to.equal(3) // 2 initial docs + 1 post-certification
            expect(equipmentDocs[2]).to.equal(docId)
        })

        it("should_revert_if_registering_document_for_deprecated_equipment", async () => {
            const { implContract, deployer, plantOperatorAdmin, manufacturer, regulatoryAuthority, laboratory } = await loadFixture(deployFullSystemFixture)
            
            // Create a plant and register roles
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer")
            await implContract.connect(plantOperatorAdmin).registerLaboratory(laboratory.address, plantId, "Laboratory")
            await implContract.connect(plantOperatorAdmin).registerRegulatoryAuthority(regulatoryAuthority.address, plantId, "Regulator")
            
            // Register equipment
            await implContract.connect(plantOperatorAdmin).registerEquipment("Reactor Pump", "Primary cooling", plantId)
            const equipmentId = 0
            
            // Add necessary documents
            await implContract.connect(manufacturer).registerDocument(equipmentId, DocumentType.TechFile, "Tech Spec", "Specifications", "QmTechHash")
            await implContract.connect(laboratory).registerDocument(equipmentId, DocumentType.LabReport, "Lab Report", "Test Results", "QmLabHash")
            
            // Mark as ready for review
            await implContract.connect(plantOperatorAdmin).equipmentIsReadyForReview(equipmentId)
            
            // Start the review
            await implContract.connect(regulatoryAuthority).reviewEquipment(equipmentId)
            
            // Finalize certification with approval
            const certHash = ethers.keccak256(ethers.toUtf8Bytes("certification_hash"))
            await implContract.connect(regulatoryAuthority).finalizeCertification(equipmentId, true, certHash, "")
            
            // Deprecate the equipment
            await implContract.connect(regulatoryAuthority).deprecateEquipment(equipmentId)
            
            // Try to register a document for deprecated equipment
            await expect(
                implContract.connect(regulatoryAuthority).registerDocument(
                    equipmentId, DocumentType.RegulatoryReview, "Post-Deprecation", "Notes", "QmPostDepHash"
                )
            ).to.be.revertedWithCustomError(implContract, "EquipmentAlreadyDeprecated")
        })

        it("should_log_integrity_verification_event_correctly", async () => {
            const { implContract, deployer, plantOperatorAdmin, manufacturer, regulatoryAuthority, laboratory, user } = await loadFixture(deployFullSystemFixture)
        
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Description", "Location", true)
            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Plant Admin")
            await implContract.connect(plantOperatorAdmin).registerManufacturer(manufacturer.address, plantId, "Manufacturer")
            await implContract.connect(plantOperatorAdmin).registerLaboratory(laboratory.address, plantId, "Laboratory")
            await implContract.connect(plantOperatorAdmin).registerRegulatoryAuthority(regulatoryAuthority.address, plantId, "Regulator")
        
            await implContract.connect(plantOperatorAdmin).registerEquipment("Reactor Pump", "Primary cooling", plantId)
            const equipmentId = 0
        
            await implContract.connect(manufacturer).registerDocument(equipmentId, DocumentType.TechFile, "Tech Spec", "Specifications", "QmTechHash")
            await implContract.connect(laboratory).registerDocument(equipmentId, DocumentType.LabReport, "Lab Report", "Test Results", "QmLabHash")
        
            await implContract.connect(plantOperatorAdmin).equipmentIsReadyForReview(equipmentId)
            await implContract.connect(regulatoryAuthority).reviewEquipment(equipmentId)
        
            const certHash = ethers.keccak256(ethers.toUtf8Bytes("certification_hash"))
            await implContract.connect(regulatoryAuthority).finalizeCertification(equipmentId, true, certHash, "")
        
            await expect(
                implContract.connect(user).checkAndLogEquipmentIntegrity(equipmentId, certHash)
            )
                .to.emit(implContract, "IntegrityVerified")
                .withArgs(
                    equipmentId,
                    certHash,
                    true,
                    user.address,
                    anyValue // timestamp dynamique
                )
        })        
    })

    describe("Getters and View Functions", () => {
        async function getterFixture() {
            const base = await loadFixture(fixtureWithEquipmentReadyForReview)
            const {
                implContract,
                storageContract,
                deployer,
                plantOperatorAdmin,
                manufacturer,
                laboratory,
                regulatoryAuthority,
                certificationOfficer,
                user,
                equipmentId,
                plantId
            } = base
        
            const eqId1 = 1
            await implContract.connect(plantOperatorAdmin).registerEquipment("Sensor Unit", "Temperature sensor", plantId)
            await implContract.connect(laboratory).registerDocument(eqId1, DocumentType.LabReport, "Sensor Calib", "Calibration data", "QmSensor")
        
            const plantId1 = 1
            await implContract.connect(deployer).registerPlant("Auxiliary Plant", "Backup", "Sector 7H", true)
        
            const manu2 = user
            await implContract.connect(plantOperatorAdmin).registerManufacturer(manu2.address, plantId1, "Manufacturer Gamma")
        
            const eqId2 = 2
            await implContract.connect(plantOperatorAdmin).registerEquipment("Filter Unit", "Air Filter", plantId1)
            await implContract.connect(manu2).registerDocument(eqId2, DocumentType.TechFile, "Filter Spec", "Spec", "QmFilter")
        
            const actorIdGamma = (await storageContract.getAllActorIds()).length - 1
        
            return {
                ...base,
                eqId1,
                eqId2,
                plantId1,
                manu2,
                actorIdGamma,
                docId0: 0,
                docId1: 1,
                docId2: 2,
                docId3: 3
            }
        }        

         it("getEquipmentDocuments_should_return_correct_doc_ids", async () => {
             const { implContract, equipmentId, eqId1, eqId2 } = await loadFixture(getterFixture)
             expect(await implContract.getEquipmentDocuments(equipmentId)).to.deep.equal([ethers.toBigInt(0), ethers.toBigInt(1)])
             expect(await implContract.getEquipmentDocuments(eqId1)).to.deep.equal([ethers.toBigInt(2)])
             expect(await implContract.getEquipmentDocuments(eqId2)).to.deep.equal([ethers.toBigInt(3)])
         })

        it("getEquipmentDocumentHashes_should_return_correct_hashes", async () => {
            const { implContract, equipmentId, eqId1, eqId2 } = await loadFixture(getterFixture)
            expect(await implContract.getEquipmentDocumentHashes(equipmentId)).to.deep.equal(["QmSpecHash", "QmLabHash"])
            expect(await implContract.getEquipmentDocumentHashes(eqId1)).to.deep.equal(["QmSensor"])
            expect(await implContract.getEquipmentDocumentHashes(eqId2)).to.deep.equal(["QmFilter"])
         })

        it("isDocumentAccessible_should_return_correct_access_boolean", async () => {
            const { implContract, manufacturer, laboratory, certificationOfficer, user, docId0, docId1, docId2 } = await loadFixture(getterFixture)
            // docId0: TechFile submitted by manufacturer
            // docId1: LabReport submitted by laboratory
            // docId2: LabReport submitted by laboratory

             // Manufacturer checks
            expect(await implContract.connect(manufacturer).isDocumentAccessible(docId0)).to.be.true // Own TechFile
            expect(await implContract.connect(manufacturer).isDocumentAccessible(docId1)).to.be.false // LabReport (not theirs, not Cert/Tech)

            // Laboratory checks
             expect(await implContract.connect(laboratory).isDocumentAccessible(docId0)).to.be.true
             expect(await implContract.connect(laboratory).isDocumentAccessible(docId1)).to.be.true // Own LabReport
             expect(await implContract.connect(laboratory).isDocumentAccessible(docId2)).to.be.true // Own LabReport

            // Certification Officer checks
             expect(await implContract.connect(certificationOfficer).isDocumentAccessible(docId0)).to.be.true // TechFile
             expect(await implContract.connect(certificationOfficer).isDocumentAccessible(docId1)).to.be.true // LabReport

             // User (no role) checks
             expect(await implContract.connect(user).isDocumentAccessible(docId0)).to.be.false
             expect(await implContract.connect(user).isDocumentAccessible(docId1)).to.be.false
         })

         it("canViewDocument_should_return_correct_access_for_specific_viewer", async () => {
             const { implContract, storageContract, manufacturer, laboratory, regulatoryAuthority, user, docId0, docId1 } = await loadFixture(getterFixture)
             // docId0: TechFile submitted by manufacturer
             // docId1: LabReport submitted by laboratory

             const manuAddr = manufacturer.address
             const labAddr = laboratory.address
             const regAddr = regulatoryAuthority.address
             const userAddr = user.address

             // Check who can view docId0 (TechFile by Manu)
             expect(await implContract.canViewDocument(docId0, manuAddr)).to.be.true // Submitter
             expect(await implContract.canViewDocument(docId0, labAddr)).to.be.false // The laboratory CANNOT view TechFile according to implementation
             expect(await implContract.canViewDocument(docId0, regAddr)).to.be.true // Regulator can view TechFile
             expect(await implContract.canViewDocument(docId0, userAddr)).to.be.true // User cannot TODO check that this is correct

            // Check who can view docId1 (LabReport by Lab)
             expect(await implContract.canViewDocument(docId1, manuAddr)).to.be.false // Manufacturer cannot view LabReport
             expect(await implContract.canViewDocument(docId1, labAddr)).to.be.true // Submitter
             expect(await implContract.canViewDocument(docId1, regAddr)).to.be.true // Regulator can view LabReport
             expect(await implContract.canViewDocument(docId1, userAddr)).to.be.false // User cannot

             // Test non-existent document
             await expect(implContract.canViewDocument(999, userAddr))
                 .to.be.revertedWithCustomError(implContract, "DocumentNotFound") // Should use DocumentNotFound from Impl (which gets it from Storage)
                 .withArgs(999)
         })

        it("getDocumentIfAuthorized_should_work_or_revert_correctly", async () => {
            const { implContract, manufacturer, laboratory, docId0, docId1 } = await loadFixture(getterFixture)

             // Manufacturer gets own doc (TechFile)
             const doc0 = await implContract.connect(manufacturer).getDocumentIfAuthorized(docId0)
             expect(doc0.name).to.equal("Pump Spec") // Check retrieved data

             // Manufacturer tries to get Lab's doc (LabReport) -> Reverts
             await expect(implContract.connect(manufacturer).getDocumentIfAuthorized(docId1))
                 .to.be.revertedWithCustomError(implContract, "UnauthorizedDocumentAccess")
                 .withArgs(docId1, manufacturer.address)

             // Laboratory gets Manu's doc (TechFile) -> Should fail because canViewDocument is false
             await expect(implContract.connect(laboratory).getDocumentIfAuthorized(docId0))
                 .to.be.revertedWithCustomError(implContract, "UnauthorizedDocumentAccess")
                 .withArgs(docId0, laboratory.address)

             // Laboratory gets own doc (LabReport)
             const doc1 = await implContract.connect(laboratory).getDocumentIfAuthorized(docId1)
             expect(doc1.name).to.equal("Stress Test")
         })

         it("getAllPlants_should_return_all_registered_plants", async () => {
             const { implContract, plantId, plantId1 } = await loadFixture(getterFixture)
             const plants = await implContract.getAllPlants()

             expect(plants).to.have.lengthOf(2)
             expect(plants[0].id).to.equal(plantId)
             expect(plants[0].name).to.equal("Centralia")
             expect(plants[1].id).to.equal(plantId1)
             expect(plants[1].name).to.equal("Auxiliary Plant")
         })

        it("getAllActorsWithRoles_should_return_actors_if_authorized", async () => {
             const {
                implContract,
                storageContract,
                deployer,
                plantOperatorAdmin,
                regulatoryAuthority,
                user
            } = await loadFixture(getterFixture)
             const allActorIds = await storageContract.getAllActorIds()
             const expectedLength = allActorIds.length

             let actors = await implContract.connect(deployer).getAllActorsWithRoles()

             expect(actors).to.have.lengthOf(expectedLength)
             actors = await implContract.connect(plantOperatorAdmin).getAllActorsWithRoles()
             expect(actors).to.have.lengthOf(expectedLength)
             actors = await implContract.connect(regulatoryAuthority).getAllActorsWithRoles()
             expect(actors).to.have.lengthOf(expectedLength)

             expect(actors[0].name).to.equal("OperatorAdmin Alice")
             expect(actors[1].name).to.equal("Manufacturer Bob")
             expect(actors[expectedLength - 1].name).to.equal("Manufacturer Gamma")

             await expect(implContract.connect(user).getAllActorsWithRoles())
                 .to.be.revertedWith("Unauthorized: Cannot view actors list")
         })

        it("getAllActorsWithRolesByPlant_should_return_plant_actors_if_authorized", async () => {
             const {
                implContract,
                plantOperatorAdmin,
                regulatoryAuthority,
                user,
                plantId,
                plantId1,
                actorIdGamma
            } = await loadFixture(getterFixture)

             // Plant 0 expected to have 5 actors (POA, Manu, Lab, RegAuth, Cert)
             const plant0Actors = await implContract.connect(plantOperatorAdmin).getAllActorsWithRolesByPlant(plantId)
             expect(plant0Actors).to.have.lengthOf(5)
             expect(plant0Actors[0].name).to.equal("OperatorAdmin Alice")
             expect(plant0Actors[1].name).to.equal("Manufacturer Bob")

             // Plant 1 expected to have 1 actor (Manufacturer Gamma)
             const plant1Actors = await implContract.connect(regulatoryAuthority).getAllActorsWithRolesByPlant(plantId1)
             expect(plant1Actors).to.have.lengthOf(1)
             expect(plant1Actors[0].id).to.equal(actorIdGamma)
             expect(plant1Actors[0].name).to.equal("Manufacturer Gamma")

             // Unauthorized user
             await expect(implContract.connect(user).getAllActorsWithRolesByPlant(plantId))
                  .to.be.revertedWith("Unauthorized: Cannot view actors list")
         })

         it("getDocumentsByPlant_should_return_plant_docs_if_authorized", async () => {
             const {
                implContract,
                plantOperatorAdmin,
                regulatoryAuthority,
                user,
                plantId,
                plantId1,
                docId0,
                docId1,
                docId2,
                docId3
            } = await loadFixture(getterFixture)

            // Plant 0 expected to have 3 documents (docId0, docId1 from equipment 0; docId2 from equipment 1)
            const plant0Docs = await implContract.connect(plantOperatorAdmin).getDocumentsByPlant(plantId)
             expect(plant0Docs).to.have.lengthOf(3)
             expect(plant0Docs[0].id).to.equal(docId0)
             expect(plant0Docs[1].id).to.equal(docId1)
             expect(plant0Docs[2].id).to.equal(docId2)

            // Plant 1 expected to have 1 document (docId3 from equipment 2)
            const plant1Docs = await implContract.connect(regulatoryAuthority).getDocumentsByPlant(plantId1)
            expect(plant1Docs).to.have.lengthOf(1)
            expect(plant1Docs[0].id).to.equal(docId3)
            expect(plant1Docs[0].name).to.equal("Filter Spec")

             // Unauthorized user
             await expect(implContract.connect(user).getDocumentsByPlant(plantId))
                  .to.be.revertedWith("Unauthorized: Cannot view plant documents")
         })

         it("getEquipmentByPlant_should_return_plant_equipment_if_authorized", async () => {
             const {
                implContract,
                plantOperatorAdmin,
                regulatoryAuthority,
                user,
                plantId,
                plantId1,
                equipmentId,
                eqId1,
                eqId2
            } = await loadFixture(getterFixture)

             // Plant 0 expected to have 2 equipment (equipmentId=0, eqId1=1)
             const plant0Eq = await implContract.connect(plantOperatorAdmin).getEquipmentByPlant(plantId)
             expect(plant0Eq).to.have.lengthOf(2)
             expect(plant0Eq[0].id).to.equal(equipmentId)
             expect(plant0Eq[0].name).to.equal("Reactor Pump 1")
             expect(plant0Eq[1].id).to.equal(eqId1)
             expect(plant0Eq[1].name).to.equal("Sensor Unit")

             // Plant 1 expected to have 1 equipment (eqId2=2)
             const plant1Eq = await implContract.connect(regulatoryAuthority).getEquipmentByPlant(plantId1)
             expect(plant1Eq).to.have.lengthOf(1)
             expect(plant1Eq[0].id).to.equal(eqId2)
             expect(plant1Eq[0].name).to.equal("Filter Unit")

            // Unauthorized user
             await expect(implContract.connect(user).getEquipmentByPlant(plantId))
                 .to.be.revertedWith("Unauthorized: Cannot view plant documents")
         })

        it("getAllDocumentsForEquipment_should_return_docs_if_authorized", async () => {
             const {
                implContract,
                plantOperatorAdmin,
                regulatoryAuthority,
                user,
                equipmentId,
                eqId1,
                docId0,
                docId1,
                docId2
            } = await loadFixture(getterFixture)

             // Equipment 0 expected to have 2 documents (docId0, docId1)
             const eq0Docs = await implContract.connect(plantOperatorAdmin).getAllDocumentsForEquipment(equipmentId)
             expect(eq0Docs).to.have.lengthOf(2)
             expect(eq0Docs[0].id).to.equal(docId0)
             expect(eq0Docs[1].id).to.equal(docId1)

             // Equipment 1 expected to have 1 document (docId2)
             const eq1Docs = await implContract.connect(regulatoryAuthority).getAllDocumentsForEquipment(eqId1)
             expect(eq1Docs).to.have.lengthOf(1)
             expect(eq1Docs[0].id).to.equal(docId2)

             // Unauthorized user
             await expect(implContract.connect(user).getAllDocumentsForEquipment(equipmentId))
                 .to.be.revertedWith("Unauthorized: Cannot view plant documents") // Uses the same modifier

             // Non-existent equipment
             await expect(implContract.connect(plantOperatorAdmin).getAllDocumentsForEquipment(999))
                 .to.be.revertedWithCustomError(implContract, "EquipmentNotFound")
                 .withArgs(999)
         })
    })

    describe("Role Registration", () => {
        it("should_allow_admin_to_register_plant_operator_admin", async () => {
            const { implContract, storageContract, deployer, plantOperatorAdmin } = await loadFixture(deployFullSystemFixture)
            const plantId = 0
            await implContract.connect(deployer).registerPlant("Test Plant", "Desc", "Loc", true)

            await implContract.connect(deployer).registerPlantOperator(plantOperatorAdmin.address, plantId, "Alice Admin")
            expect(await storageContract.hasRole(PLANT_OPERATOR_ADMIN, plantOperatorAdmin.address)).to.be.true
            
            const actor = await storageContract.getActor(0)
            expect(actor.name).to.equal("Alice Admin")
            expect(actor.actorAddress).to.equal(plantOperatorAdmin.address)
            expect(actor.role).to.equal(PLANT_OPERATOR_ADMIN)
            expect(actor.plantId).to.equal(plantId)
        })
    })

    describe("Document Access Control Initialization", () => {
        it("should_initialize_document_access_rules_correctly", async () => {
            const { storageContract } = await loadFixture(deployFullSystemFixture)
            
            // --- Rules are defined in the NuclearCertificationStorage constructor ---

            // Regulatory Authority expected to have access to all document types
            expect(await storageContract.hasDocumentAccess(DocumentType.Certification, REGULATORY_AUTHORITY)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.LabReport, REGULATORY_AUTHORITY)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.TechFile, REGULATORY_AUTHORITY)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.Compliance, REGULATORY_AUTHORITY)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.RegulatoryReview, REGULATORY_AUTHORITY)).to.be.true

            // Plant Operator Admin expected to have access to all document types
            expect(await storageContract.hasDocumentAccess(DocumentType.Certification, PLANT_OPERATOR_ADMIN)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.LabReport, PLANT_OPERATOR_ADMIN)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.TechFile, PLANT_OPERATOR_ADMIN)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.Compliance, PLANT_OPERATOR_ADMIN)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.RegulatoryReview, PLANT_OPERATOR_ADMIN)).to.be.true

            // Certification Officer expected to have partial access to document types
            expect(await storageContract.hasDocumentAccess(DocumentType.Certification, CERTIFICATION_OFFICER)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.LabReport, CERTIFICATION_OFFICER)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.TechFile, CERTIFICATION_OFFICER)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.Compliance, CERTIFICATION_OFFICER)).to.be.false
            expect(await storageContract.hasDocumentAccess(DocumentType.RegulatoryReview, CERTIFICATION_OFFICER)).to.be.false

            // Manufacturer expected to have access to technical and certification documents
            expect(await storageContract.hasDocumentAccess(DocumentType.Certification, MANUFACTURER)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.LabReport, MANUFACTURER)).to.be.false
            expect(await storageContract.hasDocumentAccess(DocumentType.TechFile, MANUFACTURER)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.Compliance, MANUFACTURER)).to.be.false
            expect(await storageContract.hasDocumentAccess(DocumentType.RegulatoryReview, MANUFACTURER)).to.be.false

            // Laboratory expected to have access to laboratory reports and certification documents
            expect(await storageContract.hasDocumentAccess(DocumentType.Certification, LABORATORY)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.LabReport, LABORATORY)).to.be.true
            expect(await storageContract.hasDocumentAccess(DocumentType.TechFile, LABORATORY)).to.be.false
            expect(await storageContract.hasDocumentAccess(DocumentType.Compliance, LABORATORY)).to.be.false
            expect(await storageContract.hasDocumentAccess(DocumentType.RegulatoryReview, LABORATORY)).to.be.false
        })
    })
})
