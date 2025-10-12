# AON CLI Cursor Rules

This directory contains development rules and guidelines for the AON CLI project, organized using the modern `.cursor/rules` directory structure.

## Rule Files

### 📋 [main.md](./main.md)
**Main development rules and project overview**
- Project architecture and structure
- Core components and patterns
- Fee structure and parameter conventions
- Development guidelines
- File organization
- Key dependencies

### 🔗 [contract-interface.md](./contract-interface.md)
**Contract interface and ABI management**
- Complete ABI definitions
- ContractManager method signatures
- Type definitions and interfaces
- Parameter naming conventions
- Error handling patterns
- Contract update procedures

### ⚡ [command-development.md](./command-development.md)
**Command development patterns and templates**
- Command structure templates
- Parameter patterns
- Display formatting
- Error handling patterns
- Spinner usage
- Confirmation patterns
- Testing guidelines

## Usage

These rules help maintain consistency and provide context for:

- **Adding new commands** - Follow the command development patterns
- **Contract updates** - Use the contract interface rules for ABI changes
- **Error handling** - Standardized patterns for user feedback
- **Parameter management** - Consistent naming and validation
- **Display formatting** - Uniform user interface patterns

## Key Benefits

- **Consistency** - Maintain consistent patterns across all commands
- **Contract Updates** - Clear procedures for handling contract interface changes
- **Error Handling** - Standardized error handling and user feedback
- **Parameter Management** - Consistent naming and validation patterns
- **Display Formatting** - Uniform user interface and information display
- **Testing** - Guidelines for comprehensive testing

## Quick Reference

### Adding a New Command
1. Follow the template in `command-development.md`
2. Use consistent parameter naming
3. Add proper validation and error handling
4. Test with various scenarios

### Updating Contract Interface
1. Update ABI in `contract-interface.md`
2. Update method signatures
3. Update related commands
4. Test all affected functionality

### Common Patterns
- Use `validateEthAmount()` for amount validation
- Use `isValidEthereumAddress()` for address validation
- Use `createSpinner()` for async operations
- Use `logError()`, `logSuccess()`, `logInfo()` for user feedback

