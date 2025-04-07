import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { ethers } from "hardhat"
import { ContractFactory } from "ethers"
import { NuclearCertificationStorage } from "../typechain-types"
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs'

describe("NuclearCertificationStorage", () => {
    // --- Constants ---
    const PLANT_OPERATOR_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("PLANT_OPERATOR_ADMIN"))
    const MANUFACTURER = ethers.keccak256(ethers.toUtf8Bytes("MANUFACTURER"))
    const LABORATORY = ethers.keccak256(ethers.toUtf8Bytes("LABORATORY"))
    const REGULATORY_AUTHORITY = ethers.keccak256(ethers.toUtf8Bytes("REGULATORY_AUTHORITY"))
    const CERTIFICATION_OFFICER = ethers.keccak256(ethers.toUtf8Bytes("CERTIFICATION_OFFICER"))
    const IMPL_ROLE = ethers.keccak256(ethers.toUtf8Bytes("IMPL_ROLE"))
    const DEFAULT_ADMIN_ROLE = ethers.ZeroHash

    // --- Fixture ---
    async function deployStorageFixture() {
        const [
            deployer,
            plantOperatorAdmin,
            manufacturer,
            laboratory,
            regulatoryAuthority,
            certificationOfficer,
            implContract,
            user1,
            user2
        ] = await ethers.getSigners()

        const StorageFactory: ContractFactory = await ethers.getContractFactory("NuclearCertificationStorage")
        const storageContract = (await StorageFactory.connect(deployer).deploy()) as NuclearCertificationStorage
        await storageContract.waitForDeployment()

        await storageContract.connect(deployer).grantRole(PLANT_OPERATOR_ADMIN, plantOperatorAdmin.address)
        await storageContract.connect(deployer).grantRole(IMPL_ROLE, implContract.address)
        await storageContract.connect(plantOperatorAdmin).grantRole(MANUFACTURER, manufacturer.address)
        await storageContract.connect(plantOperatorAdmin).grantRole(LABORATORY, laboratory.address)
        await storageContract.connect(plantOperatorAdmin).grantRole(REGULATORY_AUTHORITY, regulatoryAuthority.address)
        await storageContract.connect(plantOperatorAdmin).grantRole(CERTIFICATION_OFFICER, certificationOfficer.address)

        return {
            storageContract,
            deployer,
            plantOperatorAdmin,
            manufacturer,
            laboratory,
            regulatoryAuthority,
            certificationOfficer,
            implContract,
            user1,
            user2
        }
    }

    describe("Deployment and Initialization", () => {
        it("should_deploy_successfully_and_assign_DEFAULT_ADMIN_ROLE_to_deployer", async () => {
            const { storageContract, deployer } = await loadFixture(deployStorageFixture)
            const contractAddress = await storageContract.getAddress()
            expect(contractAddress).to.be.properAddress
            expect(await storageContract.hasRole(DEFAULT_ADMIN_ROLE, deployer.address)).to.be.true
        })

        it("should_set_correct_role_admins", async () => {
            const { storageContract } = await loadFixture(deployStorageFixture)
            expect(await storageContract.getRoleAdmin(MANUFACTURER)).to.equal(PLANT_OPERATOR_ADMIN)
            expect(await storageContract.getRoleAdmin(LABORATORY)).to.equal(PLANT_OPERATOR_ADMIN)
            expect(await storageContract.getRoleAdmin(REGULATORY_AUTHORITY)).to.equal(PLANT_OPERATOR_ADMIN)
            expect(await storageContract.getRoleAdmin(CERTIFICATION_OFFICER)).to.equal(PLANT_OPERATOR_ADMIN)
            expect(await storageContract.getRoleAdmin(IMPL_ROLE)).to.equal(DEFAULT_ADMIN_ROLE)
        })

        it("should_initialize_document_access_rules_correctly", async () => {
            const { storageContract } = await loadFixture(deployStorageFixture)
            const allDocTypes = [
                0, // Certification
                1, // Lab Report
                2, // Tech File
                3, // Compliance
                4  // Regulatory Review
            ]

            for (const docType of allDocTypes) {
                expect(await storageContract.hasDocumentAccess(docType, REGULATORY_AUTHORITY)).to.be.true
                expect(await storageContract.hasDocumentAccess(docType, PLANT_OPERATOR_ADMIN)).to.be.true
            }

            expect(await storageContract.hasDocumentAccess(0, CERTIFICATION_OFFICER)).to.be.true
            expect(await storageContract.hasDocumentAccess(1, CERTIFICATION_OFFICER)).to.be.true
            expect(await storageContract.hasDocumentAccess(2, CERTIFICATION_OFFICER)).to.be.true
            expect(await storageContract.hasDocumentAccess(3, CERTIFICATION_OFFICER)).to.be.false
            expect(await storageContract.hasDocumentAccess(4, CERTIFICATION_OFFICER)).to.be.false

            expect(await storageContract.hasDocumentAccess(0, MANUFACTURER)).to.be.true
            expect(await storageContract.hasDocumentAccess(1, MANUFACTURER)).to.be.false
            expect(await storageContract.hasDocumentAccess(2, MANUFACTURER)).to.be.true
            expect(await storageContract.hasDocumentAccess(3, MANUFACTURER)).to.be.false
            expect(await storageContract.hasDocumentAccess(4, MANUFACTURER)).to.be.false

            expect(await storageContract.hasDocumentAccess(0, LABORATORY)).to.be.true
            expect(await storageContract.hasDocumentAccess(1, LABORATORY)).to.be.true
            expect(await storageContract.hasDocumentAccess(2, LABORATORY)).to.be.false
            expect(await storageContract.hasDocumentAccess(3, LABORATORY)).to.be.false
            expect(await storageContract.hasDocumentAccess(4, LABORATORY)).to.be.false
        })

        it("should_set_implementation_contract_address_only_once_by_admin", async () => {
            const { storageContract, deployer } = await loadFixture(deployStorageFixture)
            const initialImplAddress = ethers.Wallet.createRandom().address

            await expect(storageContract.connect(deployer).setImplementationContract(initialImplAddress))
                .to.emit(storageContract, "RoleGranted")
                .withArgs(IMPL_ROLE, initialImplAddress, deployer.address)

            expect(await storageContract.hasRole(IMPL_ROLE, initialImplAddress)).to.be.true

            // Should fail because implementation already set
            await expect(storageContract.connect(deployer).setImplementationContract(ethers.Wallet.createRandom().address))
                .to.be.revertedWith("Implementation contract already set")
        })

        it("should_revert_if_implementation_address_is_zero", async () => {
            const { storageContract, deployer } = await loadFixture(deployStorageFixture)
            await expect(storageContract.connect(deployer).setImplementationContract(ethers.ZeroAddress))
                .to.be.revertedWith("Implementation address cannot be zero")
        })

        it("should_revert_if_implementation_address_is_not_admin", async () => {
            const { storageContract, user1 } = await loadFixture(deployStorageFixture)
            await expect(storageContract.connect(user1).setImplementationContract(ethers.Wallet.createRandom().address))
                .to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
                .withArgs(user1.address, DEFAULT_ADMIN_ROLE)
        })

        it("should_fail_setting_implementation_if_not_admin", async () => {
             const { storageContract, user1 } = await loadFixture(deployStorageFixture)
             await expect(storageContract.connect(user1).setImplementationContract(ethers.Wallet.createRandom().address))
                .to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
                .withArgs(user1.address, DEFAULT_ADMIN_ROLE)
        })
    })

    describe("Access Control (IMPL_ROLE)", () => {
        const plantData = { name: "Plant A", description: "Test Plant", location: "Location A", isActive: true }
        const equipmentData = { name: "EQ-001", description: "Test Equipment" }
        const documentData = { docType: 1, name: "Doc 1", description: "Test Doc", ipfsHash: "Qm..." }
        const actorData = { name: "Actor 1", role: MANUFACTURER, plantId: 0 }

        it("should_revert_createPlant_if_caller_does_not_have_IMPL_ROLE", async () => {
            const { storageContract, user1 } = await loadFixture(deployStorageFixture)
            await expect(
                storageContract.connect(user1).createPlant(user1.address, plantData.name, plantData.description, plantData.location, plantData.isActive)
            ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
             .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_revert_createEquipment_if_caller_does_not_have_IMPL_ROLE", async () => {
             const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
            await storageContract.connect(implContract).createPlant(implContract.address, plantData.name, plantData.description, plantData.location, plantData.isActive)
            const plantId = 0

            await expect(
                storageContract.connect(user1).createEquipment(user1.address, equipmentData.name, equipmentData.description, plantId)
            ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_revert_createDocument_if_caller_does_not_have_IMPL_ROLE", async () => {
             const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
            await storageContract.connect(implContract).createPlant(implContract.address, plantData.name, plantData.description, plantData.location, plantData.isActive)
            const plantId = 0
             await storageContract.connect(implContract).createEquipment(implContract.address, equipmentData.name, equipmentData.description, plantId)
            const equipmentId = 0

            await expect(
                storageContract.connect(user1).createDocument(
                    user1.address,
                    equipmentId,
                    documentData.docType,
                    documentData.name,
                    documentData.description,
                    documentData.ipfsHash
                )
            ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_revert_updateEquipmentStatus_if_caller_does_not_have_IMPL_ROLE", async () => {
             const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
             await storageContract.connect(implContract).createPlant(implContract.address, plantData.name, plantData.description, plantData.location, plantData.isActive)
             const plantId = 0
             await storageContract.connect(implContract).createEquipment(implContract.address, equipmentData.name, equipmentData.description, plantId)
             const equipmentId = 0

            await expect(
                storageContract.connect(user1).updateEquipmentStatus(user1.address, equipmentId, 1, 1)
            ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_revert_createActor_if_caller_does_not_have_IMPL_ROLE", async () => {
             const { storageContract, user1 } = await loadFixture(deployStorageFixture)
             await expect(
                 storageContract.connect(user1).createActor(actorData.name, user1.address, actorData.role, actorData.plantId)
             ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
             .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_revert_grantRoleWithCaller_if_caller_does_not_have_IMPL_ROLE", async () => {
            const { storageContract, deployer, user1, user2 } = await loadFixture(deployStorageFixture)
             await expect(
                 storageContract.connect(user1).grantRoleWithCaller(MANUFACTURER, user2.address, deployer.address)
            ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_revert_revokeRoleWithCaller_if_caller_does_not_have_IMPL_ROLE", async () => {
            const {
                storageContract,
                deployer,
                implContract,
                user1,
                user2,
                plantOperatorAdmin
            } = await loadFixture(deployStorageFixture)
        
            await storageContract.grantRole(IMPL_ROLE, implContract.address)        
            await storageContract.grantRole(PLANT_OPERATOR_ADMIN, plantOperatorAdmin.address)
        
            await storageContract.connect(implContract).grantRoleWithCaller(MANUFACTURER, user2.address, plantOperatorAdmin.address)
            expect(await storageContract.hasRole(MANUFACTURER, user2.address)).to.be.true
        
            await expect(
                storageContract.connect(user1).revokeRoleWithCaller(MANUFACTURER, user2.address, deployer.address)
            ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_revert_setFinalCertificationHash_if_caller_does_not_have_IMPL_ROLE", async () => {
            const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
            await storageContract.connect(implContract).createPlant(implContract.address, plantData.name, plantData.description, plantData.location, plantData.isActive)
            const plantId = 0
            await storageContract.connect(implContract).createEquipment(implContract.address, equipmentData.name, equipmentData.description, plantId)
            const equipmentId = 0

            const dummyHash = ethers.keccak256(ethers.toUtf8Bytes("dummy hash"))

            await expect(
                storageContract.connect(user1).setFinalCertificationHash(equipmentId, dummyHash)
            ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_revert_setRejectionReason_if_caller_does_not_have_IMPL_ROLE", async () => {
            const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
             await storageContract.connect(implContract).createPlant(implContract.address, plantData.name, plantData.description, plantData.location, plantData.isActive)
            const plantId = 0
            await storageContract.connect(implContract).createEquipment(implContract.address, equipmentData.name, equipmentData.description, plantId)
            const equipmentId = 0

            await expect(
                storageContract.connect(user1).setRejectionReason(equipmentId, "Some reason")
            ).to.be.revertedWithCustomError(storageContract, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, IMPL_ROLE)
        })

        it("should_allow_createPlant_if_caller_has_IMPL_ROLE", async () => {
            const { storageContract, implContract } = await loadFixture(deployStorageFixture)

            await expect(
                storageContract.connect(implContract).createPlant(
                    implContract.address,
                    plantData.name,
                    plantData.description,
                    plantData.location,
                    plantData.isActive
                )
            )
            .to.emit(storageContract, 'PlantRegistered')
            .withArgs(
                0, // first plantId
                plantData.name,
                implContract.address,
                anyValue // avoid timestamp
            )

            const plant = await storageContract.getPlant(0)
            expect(plant.name).to.equal(plantData.name)

            const plantIds = await storageContract.getAllPlantIds()
            expect(plantIds.length).to.equal(1)
            expect(plantIds[0]).to.equal(0)
        })

    })

    describe("Data Creation (via IMPL_ROLE)", () => {
        const plantData = { name: "Plant B", description: "Main Plant", location: "Location B", isActive: true }
        const equipmentData = { name: "EQ-101", description: "Reactor Core" }
        const documentData = { docType: 2, name: "Tech Spec v1", description: "Technical Specification", ipfsHash: "QmY..." }
        const actorData = { name: "Manu Corp", role: MANUFACTURER, plantId: 0 }

        it("should_create_a_plant_successfully", async () => {
             const { storageContract, implContract } = await loadFixture(deployStorageFixture)
             const plantId = await storageContract.connect(implContract).createPlant.staticCall(implContract.address, plantData.name, plantData.description, plantData.location, plantData.isActive)
             await storageContract.connect(implContract).createPlant(implContract.address, plantData.name, plantData.description, plantData.location, plantData.isActive)

            expect(plantId).to.equal(0)
            const plant = await storageContract.getPlant(plantId)
            expect(plant.name).to.equal(plantData.name)
            expect(plant.description).to.equal(plantData.description)
            expect(plant.location).to.equal(plantData.location)
            expect(plant.isActive).to.equal(plantData.isActive)
            expect(plant.registeredAt).to.be.gt(0)
             expect(await storageContract.getAllPlantIds()).to.deep.equal([ethers.toBigInt(0)])
        })

         it("should_create_an_equipment_and_mint_SBT_successfully", async () => {
            const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
        
            const plantId = await storageContract.connect(implContract).createPlant.staticCall(
                implContract.address,
                plantData.name,
                plantData.description,
                plantData.location,
                plantData.isActive
            )
            await storageContract.connect(implContract).createPlant(
                implContract.address,
                plantData.name,
                plantData.description,
                plantData.location,
                plantData.isActive
            )
        
            // Expectations on events
            await expect(
                storageContract.connect(implContract).createEquipment(
                    user1.address,
                    equipmentData.name,
                    equipmentData.description,
                    plantId
                )
            )
                .to.emit(storageContract, 'EquipmentRegistered')
                .withArgs(0, equipmentData.name, user1.address, anyValue)
        
                .and.to.emit(storageContract, 'Transfer')
                .withArgs(ethers.ZeroAddress, user1.address, 0) // SBT minting
        
            const equipment = await storageContract.getEquipment(0)
            expect(equipment.name).to.equal(equipmentData.name)
            expect(equipment.description).to.equal(equipmentData.description)
            expect(equipment.status).to.equal(0) // EquipmentStatus.Registered
            expect(equipment.currentStep).to.equal(0) // CertificationSteps.Registered
            expect(equipment.registeredAt).to.be.gt(0)
        
            expect(await storageContract.ownerOf(0)).to.equal(user1.address)
            expect(await storageContract.balanceOf(user1.address)).to.equal(1)
        
            expect(await storageContract.getPlantEquipmentIds(plantId)).to.deep.equal([0])
        })        

        it("should_fail_to_create_equipment_for_non_existent_plant", async () => {
             const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
             const nonExistentPlantId = 999
             await expect(
                 storageContract.connect(implContract).createEquipment(user1.address, equipmentData.name, equipmentData.description, nonExistentPlantId)
             ).to.be.revertedWithCustomError(storageContract, "PlantNotFound")
             .withArgs(nonExistentPlantId)
         })

         it("should_create_a_document_successfully", async () => {
            const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
        
            const plantId = await storageContract.connect(implContract).createPlant.staticCall(
                implContract.address,
                plantData.name,
                plantData.description,
                plantData.location,
                plantData.isActive
            )
            await storageContract.connect(implContract).createPlant(
                implContract.address,
                plantData.name,
                plantData.description,
                plantData.location,
                plantData.isActive
            )
        
            await storageContract.connect(implContract).createEquipment(
                user1.address,
                equipmentData.name,
                equipmentData.description,
                plantId
            )
        
            await expect(
                storageContract.connect(implContract).createDocument(
                    user1.address,
                    0,
                    documentData.docType,
                    documentData.name,
                    documentData.description,
                    documentData.ipfsHash
                )
            )
                .to.emit(storageContract, 'DocumentSubmitted')
                .withArgs(0, 0, documentData.docType, user1.address, anyValue)
        
            const doc = await storageContract.getDocument(0)
            expect(doc.name).to.equal(documentData.name)
            expect(doc.description).to.equal(documentData.description)
            expect(doc.docType).to.equal(documentData.docType)
            expect(doc.status).to.equal(0)
            expect(doc.ipfsHash).to.equal(documentData.ipfsHash)
            expect(doc.submittedAt).to.be.gt(0)
        
            const equipmentDocs = await storageContract.getEquipmentDocuments(0)
            expect(equipmentDocs).to.deep.equal([0])
        })

        it("should_fail_to_create_document_for_non_existent_equipment", async () => {
            const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
            const nonExistentEquipmentId = 999
            await expect(
                 storageContract.connect(implContract).createDocument(
                     user1.address, nonExistentEquipmentId, documentData.docType, documentData.name, documentData.description, documentData.ipfsHash
                 )
             ).to.be.revertedWithCustomError(storageContract, "EquipmentNotFound")
             .withArgs(nonExistentEquipmentId)
        })

        it("should_create_an_actor_successfully", async () => {
            const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
        
            await storageContract.connect(implContract).createPlant(
                implContract.address,
                plantData.name,
                plantData.description,
                plantData.location,
                plantData.isActive
            )
        
            await storageContract.connect(implContract).createActor(
                actorData.name,
                user1.address,
                actorData.role,
                0n // plantId by default
            )
        
            const actor = await storageContract.getActor(0n)
            expect(actor.name).to.equal(actorData.name)
            expect(actor.actorAddress).to.equal(user1.address)
            expect(actor.role).to.equal(actorData.role)
            expect(actor.plantId).to.equal(0n)
            expect(actor.registeredAt).to.be.gt(0)
        
            expect(await storageContract.getAllActorIds()).to.deep.equal([0n])
            expect(await storageContract.getPlantActorIds(0n)).to.deep.equal([0n])
        })        

        it("should_create_an_actor_even_if_plant_does_not_exist_or_plantId_is_0", async () => {
            const { storageContract, implContract, user1 } = await loadFixture(deployStorageFixture)
            const nonExistentPlantId = 999
            const actorId = await storageContract.connect(implContract).createActor.staticCall(
                 "Actor No Plant", user1.address, MANUFACTURER, nonExistentPlantId
             )
            await storageContract.connect(implContract).createActor("Actor No Plant", user1.address, MANUFACTURER, nonExistentPlantId)

            expect(actorId).to.equal(0)
            const actor = await storageContract.getActor(actorId)
            expect(actor.name).to.equal("Actor No Plant")
            expect(actor.plantId).to.equal(nonExistentPlantId)

            expect(await storageContract.getAllActorIds()).to.deep.equal([ethers.toBigInt(0)])
            expect(await storageContract.getPlantActorIds(nonExistentPlantId)).to.deep.equal([])
        })
    })

    describe("Soulbound Token (ERC721 Functionality)", () => {
    it("should_prevent_transferFrom", async () => {
        const { storageContract, implContract, user1, user2 } = await loadFixture(deployStorageFixture)
        await storageContract.connect(implContract).createPlant(implContract.address, "Name", "Desc", "Loc", true)
        await storageContract.connect(implContract).createEquipment(user1.address, "Name", "Desc", 0)
        const tokenId = 0

        expect(await storageContract.ownerOf(tokenId)).to.equal(user1.address)

        await expect(
            storageContract.connect(user1).transferFrom(user1.address, user2.address, tokenId)
        ).to.be.revertedWithCustomError(storageContract, "SoulboundTokenNonTransferableAndNotBurnable")
            .withArgs(tokenId)
    })

    it("should_prevent_safeTransferFrom", async () => {
        const { storageContract, implContract, user1, user2 } = await loadFixture(deployStorageFixture)
            await storageContract.connect(implContract).createPlant(implContract.address, "Name", "Desc", "Loc", true)
        await storageContract.connect(implContract).createEquipment(user1.address, "Name", "Desc", 0)
        const tokenId = 0

            await expect(
                storageContract.connect(user1)["safeTransferFrom(address,address,uint256)"](user1.address, user2.address, tokenId)
        ).to.be.revertedWithCustomError(storageContract, "SoulboundTokenNonTransferableAndNotBurnable")
            .withArgs(tokenId)

        await expect(
            storageContract.connect(user1)["safeTransferFrom(address,address,uint256,bytes)"](user1.address, user2.address, tokenId, "0x1234")
            ).to.be.revertedWithCustomError(storageContract, "SoulboundTokenNonTransferableAndNotBurnable")
            .withArgs(tokenId)
        })

        it("should_prevent_approve", async () => {
            const { storageContract, implContract, user1, user2 } = await loadFixture(deployStorageFixture)
            await storageContract.connect(implContract).createPlant(implContract.address, "Name", "Desc", "Loc", true)
            await storageContract.connect(implContract).createEquipment(user1.address, "Name", "Desc", 0)
            const tokenId = 0

            await expect(
                storageContract.connect(user1).approve(user2.address, tokenId)
            ).to.be.revertedWithCustomError(storageContract, "SoulboundTokenNonTransferableAndNotBurnable")
            .withArgs(tokenId)
        })

        it("should_prevent_setApprovalForAll", async () => {
            const { storageContract, user1, user2 } = await loadFixture(deployStorageFixture)
            await expect(
                storageContract.connect(user1).setApprovalForAll(user2.address, true)
            ).to.be.revertedWithCustomError(storageContract, "SoulboundTokenNonTransferableAndNotBurnable")
            .withArgs(0)
        })
    })

    describe("Role Management (via IMPL_ROLE and grantRoleWithCaller)", () => {
        it("should_allow_admin_to_grant_roles_via_implContract", async () => {
            const { storageContract, implContract, plantOperatorAdmin, user1 } = await loadFixture(deployStorageFixture)
        
            await storageContract.grantRole(PLANT_OPERATOR_ADMIN, plantOperatorAdmin.address)
        
            await expect(
                storageContract.connect(implContract).grantRoleWithCaller(MANUFACTURER, user1.address, plantOperatorAdmin.address)
            )
                .to.emit(storageContract, "RoleGranted")
                .withArgs(MANUFACTURER, user1.address, implContract.address)
        
            expect(await storageContract.hasRole(MANUFACTURER, user1.address)).to.be.true
        })        

        it("should_prevent_non_admin_from_granting_roles_via_implContract", async () => {
             const { storageContract, user1, implContract, user2 } = await loadFixture(deployStorageFixture)

             await expect(
                 storageContract.connect(implContract).grantRoleWithCaller(MANUFACTURER, user2.address, user1.address)
             ).to.be.revertedWith("Caller doesn't have admin role")
         })

        it("should_allow_admin_to_revoke_roles_via_implContract", async () => {
            const { storageContract, manufacturer, implContract, user1 } = await loadFixture(deployStorageFixture)
        
            await storageContract.grantRole(PLANT_OPERATOR_ADMIN, manufacturer.address)
        
            await storageContract.connect(implContract).grantRoleWithCaller(
                MANUFACTURER,
                user1.address,
                manufacturer.address
            )
            expect(await storageContract.hasRole(MANUFACTURER, user1.address)).to.be.true
        
            await expect(
                storageContract.connect(implContract).revokeRoleWithCaller(
                    MANUFACTURER,
                    user1.address,
                    manufacturer.address
                )
            )
                .to.emit(storageContract, "RoleRevoked(bytes32,address,address)")
                .withArgs(MANUFACTURER, user1.address, implContract.address)
            
        
            expect(await storageContract.hasRole(MANUFACTURER, user1.address)).to.be.false
        })        

        it("should_prevent_non_admin_from_revoking_roles_via_implContract", async () => {
            const { storageContract, manufacturer, user1, implContract, user2 } = await loadFixture(deployStorageFixture)
        
            await storageContract.grantRole(PLANT_OPERATOR_ADMIN, manufacturer.address)
        
            await storageContract.connect(implContract).grantRoleWithCaller(
                MANUFACTURER,
                user2.address,
                manufacturer.address
            )
        
            expect(await storageContract.hasRole(MANUFACTURER, user2.address)).to.be.true
        
            await expect(
                storageContract.connect(implContract).revokeRoleWithCaller(
                    MANUFACTURER,
                    user2.address,
                    user1.address
                )
            ).to.be.revertedWith("Caller doesn't have admin role")
        })        
    })

     describe("Getter Functions", () => {
        async function deployWithDataFixture() {
            const base = await loadFixture(deployStorageFixture)
            const { storageContract, implContract, deployer, user1, user2 } = base

            await storageContract.connect(implContract).createPlant(implContract.address, "Plant X", "Desc X", "Loc X", true)
            await storageContract.connect(implContract).createPlant(implContract.address, "Plant Y", "Desc Y", "Loc Y", false)

            await storageContract.connect(implContract).createEquipment(user1.address, "Name X", "Desc X", 0)
            await storageContract.connect(implContract).createEquipment(user2.address, "Name Y", "Desc Y", 0)
            await storageContract.connect(implContract).createEquipment(user1.address, "Name Z", "Desc Z", 1)

            await storageContract.connect(implContract).createDocument(
                user1.address,
                0, // equipmentId
                2, // doctype TechFile
                "Doc Name X",
                "Desc Doc X",
                "ipfsHashX"
            )
            await storageContract.connect(implContract).createDocument(
                user2.address, 
                0, // equipmentId
                1, // doctype LabReport
                "Doc Name Y",
                "Desc Doc Y",
                "ipfsHashY"
            )
            await storageContract.connect(implContract).createDocument(
                user1.address, 
                2, // equipmentId
                0, // doctype Certification
                "Doc Name Z",
                "Desc Doc Z",
                "ipfsHashZ"
            )

            await storageContract.connect(implContract).createActor("Manu X", user1.address, MANUFACTURER, 0)
            await storageContract.connect(implContract).createActor("Lab Y", user2.address, LABORATORY, 1)
            await storageContract.connect(implContract).createActor("ASN Z", deployer.address, REGULATORY_AUTHORITY, 999)

            return base
        }

         it("should_return_correct_plant_data", async () => {
             const { storageContract } = await loadFixture(deployWithDataFixture)
             const plant0 = await storageContract.getPlant(0)
             expect(plant0.name).to.equal("Plant X")
             expect(plant0.isActive).to.be.true

             const plant1 = await storageContract.getPlant(1)
             expect(plant1.name).to.equal("Plant Y")
             expect(plant1.isActive).to.be.false
         })

        it("should_return_correct_equipment_data", async () => {
            const { storageContract } = await loadFixture(deployWithDataFixture)
            const eq0 = await storageContract.getEquipment(0)
            expect(eq0.name).to.equal("Name X")
            expect(eq0.status).to.equal(0)
        })

        it("should_return_correct_document_data", async () => {
             const { storageContract } = await loadFixture(deployWithDataFixture)
             const doc1 = await storageContract.getDocument(1)
             expect(doc1.name).to.equal("Doc Name Y")
             expect(doc1.docType).to.equal(1)
             expect(doc1.ipfsHash).to.equal("ipfsHashY")
         })

        it("should_return_correct_actor_data", async () => {
            const { storageContract, user2 } = await loadFixture(deployWithDataFixture)
            const actor1 = await storageContract.getActor(1)
            expect(actor1.name).to.equal("Lab Y")
            expect(actor1.actorAddress).to.equal(user2.address)
            expect(actor1.role).to.equal(LABORATORY)
            expect(actor1.plantId).to.equal(1)
         })

        it("should_return_correct_equipment_documents", async () => {
             const { storageContract } = await loadFixture(deployWithDataFixture)
             const eq0Docs = await storageContract.getEquipmentDocuments(0)
             expect(eq0Docs).to.deep.equal([ethers.toBigInt(0), ethers.toBigInt(1)])

             const eq1Docs = await storageContract.getEquipmentDocuments(1)
             expect(eq1Docs).to.deep.equal([])

             const eq2Docs = await storageContract.getEquipmentDocuments(2)
             expect(eq2Docs).to.deep.equal([ethers.toBigInt(2)])
         })

        it("should_return_correct_document_access", async () => {
            const { storageContract } = await loadFixture(deployWithDataFixture)
             expect(await storageContract.hasDocumentAccess(2, MANUFACTURER)).to.be.true
             expect(await storageContract.hasDocumentAccess(1, MANUFACTURER)).to.be.false
             expect(await storageContract.hasDocumentAccess(1, REGULATORY_AUTHORITY)).to.be.true
         })

        it("should_return_all_plant_ids", async () => {
             const { storageContract } = await loadFixture(deployWithDataFixture)
             expect(await storageContract.getAllPlantIds()).to.deep.equal([ethers.toBigInt(0), ethers.toBigInt(1)])
         })

        it("should_return_all_actor_ids", async () => {
             const { storageContract } = await loadFixture(deployWithDataFixture)
             expect(await storageContract.getAllActorIds()).to.deep.equal([ethers.toBigInt(0), ethers.toBigInt(1), ethers.toBigInt(2)])
         })

        it("should_return_correct_plant_equipment_ids", async () => {
            const { storageContract } = await loadFixture(deployWithDataFixture)
             expect(await storageContract.getPlantEquipmentIds(0)).to.deep.equal([ethers.toBigInt(0), ethers.toBigInt(1)])
             expect(await storageContract.getPlantEquipmentIds(1)).to.deep.equal([ethers.toBigInt(2)])
            expect(await storageContract.getPlantEquipmentIds(999)).to.deep.equal([])
         })

        it("should_return_correct_plant_actor_ids", async () => {
            const { storageContract } = await loadFixture(deployWithDataFixture)
            expect(await storageContract.getPlantActorIds(0)).to.deep.equal([ethers.toBigInt(0)])
            expect(await storageContract.getPlantActorIds(1)).to.deep.equal([ethers.toBigInt(1)])
            expect(await storageContract.getPlantActorIds(999)).to.deep.equal([])
        })
    })

    describe("Helper Functions", () => {
        it("should_convert_bytes32_to_hex_string_correctly", async () => {
             const { storageContract } = await loadFixture(deployStorageFixture)
             const testBytes32 = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
             const expectedString = testBytes32.toLowerCase()
             const result = await storageContract.bytes32ToHexString(testBytes32)
             expect(result).to.equal(expectedString)

            const zeroBytes32 = ethers.ZeroHash
             const expectedZeroString = "0x0000000000000000000000000000000000000000000000000000000000000000"
             const zeroResult = await storageContract.bytes32ToHexString(zeroBytes32)
             expect(zeroResult).to.equal(expectedZeroString)
         })
    })
})
