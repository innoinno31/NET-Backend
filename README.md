# Nuclear Equipment Traceability (NET)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

## 🧾 Description

**NET** est une solution blockchain pour la traçabilité et la certification des équipements nucléaires.  
Elle assure un suivi rigoureux et transparent de la documentation technique, des inspections, et des certifications, tout au long du cycle de vie des équipements.

## ✨ Fonctionnalités

- **Gestion des centrales** – Enregistrement et suivi des sites nucléaires
- **Suivi des équipements** – Association des équipements aux centrales et historique
- **Gestion documentaire** – Téléversement sécurisé des documents via IPFS
- **Certification** – Processus clair et auditable de validation réglementaire
- **Contrôle d'accès par rôle** :
  - Opérateur de centrale
  - Fabricant
  - Laboratoire
  - Autorité réglementaire
  - Agent de certification
- **Vérification d'intégrité** – Chaque document est haché et vérifiable sur la blockchain

## ⚙️ Architecture technique

Le système repose sur une architecture en deux contrats séparés :

- `NuclearCertificationStorage.sol` – Stocke les données (ERC721 pour équipements)
- `NuclearCertificationImpl.sol` – Gère la logique métier (soumissions, rôles, statuts...)

Cette séparation est gérée par **Hardhat Ignition**, qui établit le lien entre les deux au moment du déploiement.

## 🛠️ Installation

```bash
# Cloner le dépôt
git clone https://github.com/innoinno31/NET-Backend.git
cd net-backend

# Installer les dépendances
npm install

# Compiler les contrats
npx hardhat compile

# Lancer les tests
npx hardhat test
```

## 🚀 Déploiement

### Réseau de test Sepolia

Le déploiement s'effectue à l'aide de **Hardhat Ignition** :

```bash
npx hardhat ignition deploy ignition/modules/NuclearCertificationImplModule.ts --network sepolia
```

Cette commande :
- Déploie automatiquement le contrat NuclearCertificationStorage
- Déploie le contrat NuclearCertificationImpl
- Lie les deux en appelant setImplementationContract(...) sur le Storage

### ⚠️ Pré-requis

Assurez-vous que votre fichier hardhat.config.ts est correctement configuré avec :
- url: une URL RPC Sepolia (ex : Infura, Alchemy, etc.)
- accounts: une clé privée (via .env sécurisé)

## 🔐 Rôles et autorisations

| Rôle | Description |
|------|-------------|
| PLANT_OPERATOR_ADMIN | Administrateurs des centrales |
| MANUFACTURER | Fabricants d'équipements |
| LABORATORY | Laboratoires techniques et de test |
| REGULATORY_AUTHORITY | Autorité réglementaire (ex: ASN, IRSN) |
| CERTIFICATION_OFFICER | Agents de certification |

## 🧪 Cycle de vie d'une certification

1. Enregistrement de l'équipement
2. Soumission des documents nécessaires
3. Passage en statut "prêt pour examen"
4. Évaluation par un certificateur ou l'autorité
5. Certification ou rejet
6. Vérification publique via une page dédiée