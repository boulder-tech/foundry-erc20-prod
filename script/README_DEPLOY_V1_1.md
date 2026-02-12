# Deploy y Upgrade a v1.1 en Base Sepolia

Este documento describe el proceso completo para deployar y hacer upgrade de los contratos engine y token de v1.0 a v1.1 en Base Sepolia.

## Prerequisitos

1. **Variables de entorno** (agregar a `.env`):
   ```bash
   BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
   BASESCAN_API_KEY=tu_api_key_de_basescan
   PRIVATE_KEY=tu_private_key_del_owner
   ENGINE_OWNER=0x...  # Opcional: dirección del owner del engine
   TOKEN_OWNER=0x...   # Opcional: dirección del owner del token (para upgrades)
   ```

2. **Direcciones de contratos existentes** (si ya están deployados):
   - `ENGINE_PROXY`: Dirección del proxy del engine v1.0
   - `TOKEN_PROXY`: Dirección del proxy del token v1.0 (para upgrades)

## Flujo de Upgrade (v1.0 → v1.1)

### Paso 1: Upgrade del Engine a v1.1

**IMPORTANTE**: El engine debe estar desplegado y funcionando en v1.0.

1. Editar `script/UpgradeEngineToV1_1.s.sol` y establecer `ENGINE_PROXY`:
   ```solidity
   address public constant ENGINE_PROXY = 0x...; // Tu dirección del engine proxy
   ```

2. Ejecutar el script:
   ```bash
   forge script script/UpgradeEngineToV1_1.s.sol:UpgradeEngineToV1_1 \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast \
     --verify \
     --etherscan-api-key $BASESCAN_API_KEY \
     -vvvv
   ```

3. Verificar:
   - El engine debe reportar versión "1.1"
   - El engine debe estar unpaused
   - El estado debe preservarse

### Paso 2: Deploy Token v1.1 Implementation y Configurar en Engine

Después de upgradear el engine, necesitas deployar la implementación v1.1 del token y configurarla en el engine para que los nuevos tokens usen v1.1.

1. Editar `script/SetTokenImplementationV1_1.s.sol` y establecer `ENGINE_PROXY`:
   ```solidity
   address public constant ENGINE_PROXY = 0x...; // Misma dirección del engine proxy
   ```

2. Ejecutar el script:
   ```bash
   forge script script/SetTokenImplementationV1_1.s.sol:SetTokenImplementationV1_1 \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast \
     --verify \
     --etherscan-api-key $BASESCAN_API_KEY \
     -vvvv
   ```

3. Verificar:
   - `engine.s_tokenImplementationAddress()` debe apuntar a la nueva implementación v1.1
   - Los nuevos tokens creados serán v1.1 automáticamente

### Paso 3: Upgrade de Tokens Existentes a v1.1

Para cada token existente que quieras upgradear:

1. Editar `script/UpgradeTokenToV1_1.s.sol` y establecer:
   ```solidity
   address public constant TOKEN_PROXY = 0x...; // Dirección del token proxy
   address public constant ENGINE_PROXY = 0x...; // Dirección del engine proxy
   ```

2. Ejecutar el script:
   ```bash
   forge script script/UpgradeTokenToV1_1.s.sol:UpgradeTokenToV1_1 \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast \
     --verify \
     --etherscan-api-key $BASESCAN_API_KEY \
     -vvvv
   ```

3. Verificar:
   - El token debe reportar versión "1.1"
   - El estado del token debe preservarse
   - Las funciones nuevas de v1.1 deben estar disponibles

## Orden de Ejecución

```
1. UpgradeEngineToV1_1.s.sol
   ↓
2. SetTokenImplementationV1_1.s.sol
   ↓
3. UpgradeTokenToV1_1.s.sol (para cada token existente)
```

## Consideraciones Importantes

### Seguridad

- ✅ Todos los upgrades requieren que el engine esté pausado
- ✅ Solo el owner puede ejecutar upgrades
- ✅ El storage layout es compatible (variables nuevas al final usando `__gap`)
- ✅ Los tests de upgrade pasan completamente

### Estado Preservado

- ✅ Todos los mappings y state variables se preservan
- ✅ Los tokens existentes siguen funcionando después del upgrade del engine
- ✅ Los tokens deben upgradearse individualmente para usar funciones v1.1

### Nuevos Tokens

- Después del Paso 2, todos los tokens nuevos creados con `createToken()` serán v1.1 automáticamente
- El engine registrará el access manager de cada nuevo token en `s_accessManagerForDeployedTokens`

### Tokens Existentes

- Los tokens creados en v1.0 NO tienen registro en `s_accessManagerForDeployedTokens`
- Puedes usar `changeTokenAccessManager()` después de upgradear el token a v1.1
- El engine registrará el nuevo manager en el mapping

## Verificación Post-Upgrade

Después de completar todos los pasos, verifica:

1. **Engine**:
   ```solidity
   engine.getVersion() == "1.1"
   engine.s_tokenImplementationAddress() == tokenV1_1Implementation
   !engine.isEnginePaused()
   ```

2. **Tokens nuevos**:
   ```solidity
   token.getVersion() == "1.1"
   engine.getAccessManagerForDeployedToken(salt) == managerAddress
   ```

3. **Tokens upgradeados**:
   ```solidity
   token.getVersion() == "1.1"
   token.setAccessManager() disponible
   engine.changeTokenAccessManager() funciona
   ```

## Troubleshooting

### Error: "Engine must be v1.1"
- Asegúrate de haber ejecutado `UpgradeEngineToV1_1.s.sol` primero

### Error: "Caller is not the owner"
- Verifica que estás usando la private key del owner correcto
- Puedes establecer `ENGINE_OWNER` o `TOKEN_OWNER` en `.env`

### Error: "Engine is already paused"
- El script maneja esto automáticamente, pero si persiste, verifica el estado del engine

### Error: "Token v1.1 implementation not set"
- Ejecuta `SetTokenImplementationV1_1.s.sol` antes de upgradear tokens

## Testing Local

Antes de deployar en Base Sepolia, puedes probar localmente:

```bash
# Ejecutar tests de upgrade
forge test --match-contract "UpgradeV1_0_to_V1_1" -vvv

# Simular deploy en Anvil
anvil
# En otra terminal:
forge script script/UpgradeEngineToV1_1.s.sol:UpgradeEngineToV1_1 \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

## Referencias

- Tests de upgrade: `test/v1.1/UpgradeV1_0_to_V1_1.t.sol`
- Documentación de upgrade: `test/v1.1/README_UpgradeV1_0_to_V1_1.md`
- Storage layout: Ver comentarios en `src/BTContracts/v1.1/BTtokensEngine_v1.sol` línea 575+
