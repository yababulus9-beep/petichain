# Petichain 🗂️

**On-Chain Petition Platform with Verified Digital Signatures**

Petichain is a decentralized petition platform built on the Stacks blockchain using Clarity smart contracts. It enables the creation and management of transparent, tamper-proof petitions with verified digital signatures from participants.

## Overview

Petichain revolutionizes digital activism by providing a trustless, transparent platform where petitions and their signatures are permanently recorded on the blockchain. Each petition is immutable once created, and all signatures are cryptographically verified and publicly auditable.

## Key Features

### 📝 **Petition Creation**
- Create petitions with title, description, target signature goal, and deadline
- Immutable petition data stored on-chain
- Automatic petition ID generation
- Public visibility and accessibility

### ✍️ **Digital Signature Verification**
- Cryptographic signature validation
- Anti-spam protection with signature limits
- Duplicate signature prevention
- Real-time signature counting

### 🔒 **Security & Transparency**
- All data permanently stored on blockchain
- Tamper-proof petition records
- Public audit trail for all actions
- Decentralized verification system

### ⏰ **Time-Based Management**
- Deadline enforcement for petition signing
- Automatic petition status updates
- Historical petition archiving

## Smart Contract Architecture

### 1. **Petition Manager Contract** (`petition-manager.clar`)
- Core petition creation and management
- Petition metadata storage and retrieval
- Status tracking and validation
- Goal achievement verification

### 2. **Signature Validator Contract** (`signature-validator.clar`)
- Digital signature verification and storage
- Anti-duplicate signature enforcement
- Signature counting and statistics
- Signer authentication and tracking

## Technical Specifications

### Data Structures

**Petition Object:**
```clarity
{
  id: uint,
  title: (string-ascii 200),
  description: (string-utf8 1000),
  creator: principal,
  target-signatures: uint,
  current-signatures: uint,
  deadline: uint,
  created-at: uint,
  status: (string-ascii 20)
}
```

**Signature Object:**
```clarity
{
  petition-id: uint,
  signer: principal,
  signature: (buff 65),
  signed-at: uint,
  verified: bool
}
```

### Key Functions

#### Petition Management
- `create-petition`: Create a new petition with specified parameters
- `get-petition`: Retrieve petition details by ID
- `get-petition-count`: Get total number of petitions created
- `check-petition-status`: Verify if petition is active and accepting signatures

#### Signature Operations
- `sign-petition`: Submit a verified signature to a petition
- `verify-signature`: Cryptographically verify signature authenticity
- `get-signature-count`: Get current signature count for a petition
- `has-signed`: Check if a principal has already signed a petition

### Security Features

1. **Signature Verification**: All signatures are cryptographically validated before acceptance
2. **Duplicate Prevention**: Each principal can only sign a petition once
3. **Deadline Enforcement**: Signatures are only accepted before petition deadline
4. **Input Validation**: All user inputs are validated for type safety and bounds
5. **Access Control**: Proper authorization checks for sensitive operations

## Usage Examples

### Creating a Petition
```clarity
(create-petition 
  "Save the Environment"
  "A petition to implement stronger environmental protection laws"
  u1000
  u1640995200) ;; Unix timestamp for deadline
```

### Signing a Petition
```clarity
(sign-petition 
  u1 
  0x1234567890abcdef...) ;; 65-byte signature
```

### Checking Petition Status
```clarity
(get-petition u1)
```

## Development Setup

### Prerequisites
- Clarinet CLI installed
- Node.js and npm
- Git

### Installation
1. Clone the repository
2. Install dependencies: `npm install`
3. Run tests: `npm test`
4. Check contracts: `clarinet check`

### Testing
The project includes comprehensive test suites covering:
- Petition creation and validation
- Signature verification and storage
- Edge cases and error conditions
- Security and access control

## Security Considerations

- **Signature Replay Protection**: Each signature includes petition-specific context
- **Time-based Security**: Deadlines prevent indefinite signature collection
- **Principal Authentication**: Stacks blockchain handles identity verification
- **Data Immutability**: Once written, petition data cannot be modified

## Future Enhancements

- Multi-signature petition approval
- Petition categories and tags
- Voting weight based on token holdings
- Integration with governance frameworks
- Mobile application interface

## Contributing

We welcome contributions to improve Petichain. Please follow the standard GitHub workflow:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is open source and available under the MIT License.

## Contact

For questions, suggestions, or support, please open an issue on GitHub.

---

**Petichain: Empowering Digital Democracy Through Blockchain Technology** 🚀
