# Deploy y Upgrade a v1.1 en Base Sepolia

Este documento describe el proceso completo para deployar y hacer upgrade de los contratos engine y token de v1.0 a v1.1 en Base Sepolia.

## Prerequisitos

1. **Variables de entorno** (agregar a `.env`):
   ```bash
   BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
   BASESCAN_API_KEY=tu_api_key_de_basescan
   PRIVATE_KEY=tu_private_key_del_owner
   ENGINE_PROXY=0x...   # Dirección del proxy del engine (v1.0 para upgrade; obligatoria para el script de upgrade)
   ENGINE_OWNER=0x...  # Opcional: dirección del owner del engine (por defecto la clave que firma)
   TOKEN_OWNER=0x...   # Opcional: dirección del owner del token (para upgrades)
   ```

2. **Direcciones de contratos existentes** (si ya están deployados):
   - `ENGINE_PROXY`: obligatoria para el script de upgrade del engine (env o .env)
   - `TOKEN_PROXY`: dirección del proxy del token v1.0 para upgrades de tokens

## Flujo de Upgrade (v1.0 → v1.1)

### Paso 1: Upgrade del Engine a v1.1

**IMPORTANTE**: El engine debe estar desplegado y funcionando en v1.0.

1. Definir la dirección del engine proxy (en `.env` o exportar):
   ```bash
   export ENGINE_PROXY=0x...   # tu dirección del engine proxy v1.0
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

## Verificación de Contratos en BaseScan

### Verificación Automática

Cuando ejecutas los scripts con el flag `--verify`, Foundry intenta verificar automáticamente todos los contratos deployados en BaseScan:

- **Nueva implementación del engine v1.1**: Se deploya en `UpgradeEngineToV1_1.s.sol` (línea 53)
- **Nueva implementación del token v1.1**: Se deploya en `SetTokenImplementationV1_1.s.sol`
- **Cualquier otro contrato deployado durante el broadcast**

La verificación se hace automáticamente usando tu `BASESCAN_API_KEY` configurada en `foundry.toml`.

### Verificación Manual (si falla la automática)

Si la verificación automática falla, puedes verificar manualmente:

#### Engine v1.1 Implementation:
```bash
forge verify-contract <ENGINE_V1_1_IMPLEMENTATION_ADDRESS> \
  src/BTContracts/v1.1/BTtokensEngine_v1.sol:BTtokensEngine_v1 \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY \
  --compiler-version 0.8.24 \
  --num-of-optimizations 200 \
  --constructor-args $(cast abi-encode "constructor()")
```

#### Token v1.1 Implementation:
```bash
forge verify-contract <TOKEN_V1_1_IMPLEMENTATION_ADDRESS> \
  src/BTContracts/v1.1/BTtokens_v1.sol:BTtokens_v1 \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY \
  --compiler-version 0.8.24 \
  --num-of-optimizations 200 \
  --constructor-args $(cast abi-encode "constructor()")
```

**Nota importante**: Solo se verifica la nueva implementación, NO el proxy. El proxy ya está verificado y apunta a la nueva implementación después del upgrade.

**URLs de BaseScan**:
- Base Sepolia Explorer: `https://sepolia.basescan.org/address/<ADDRESS>`
- Chain ID: `84532`

## Verificación Post-Upgrade

Después de completar todos los pasos, verifica:

1. **Engine**:
   ```solidity
   engine.getVersion() == "1.1"
   engine.s_tokenImplementationAddress() == tokenV1_1Implementation
   !engine.isEnginePaused()
   ```
   - Verifica en BaseScan que la nueva implementación esté verificada
   - El proxy debe mostrar la nueva implementación en "Implementation"

2. **Tokens nuevos**:
   ```solidity
   token.getVersion() == "1.1"
   engine.getAccessManagerForDeployedToken(salt) == managerAddress
   ```
   - Verifica en BaseScan que el token use la implementación v1.1

3. **Tokens upgradeados**:
   ```solidity
   token.getVersion() == "1.1"
   token.setAccessManager() disponible
   engine.changeTokenAccessManager() funciona
   ```
   - Verifica en BaseScan que el token proxy apunte a la implementación v1.1

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

### Error: "Verification failed" o "Contract verification failed"
- La verificación automática puede fallar por timeout o problemas de red
- Usa los comandos de verificación manual mencionados arriba
- Asegúrate de tener la `BASESCAN_API_KEY` correcta en `.env`
- Verifica que el compilador y optimizaciones coincidan con el deploy

## Testing Local

Antes de deployar en Base Sepolia, puedes probar localmente.

### 1. Tests de upgrade (sin Anvil)

```bash
forge test --match-contract "UpgradeV1_0_to_V1_1" -vvv
```

### 2. Simular upgrade en Anvil (deploy v1.0 + upgrade a v1.1)

El script de upgrade requiere que **ENGINE_PROXY** esté definido (variable de entorno). En local primero debes desplegar e inicializar el engine v1.0, luego exportar esa dirección y ejecutar el upgrade.

**Terminal 1 – levantar Anvil:**

```bash
anvil
```

**Terminal 2 – desplegar e inicializar engine v1.0:**

```bash
forge script script/DeployAndInitEngine.s.sol:DeployAndInitEngine \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

Copia la dirección que imprime **Engine Proxy** (algo como `0x5FbDB2315678afecb367f032d93F642f64180aa3`).

**Exportar ENGINE_PROXY y ejecutar el upgrade:**

```bash
export ENGINE_PROXY=0x...   # la dirección del Engine Proxy del paso anterior

forge script script/UpgradeEngineToV1_1.s.sol:UpgradeEngineToV1_1 \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

Si no defines `ENGINE_PROXY`, el script falla con: `ENGINE_PROXY must be set (export ENGINE_PROXY=0x... or add to .env)`.

## Referencias

- Tests de upgrade: `test/v1.1/UpgradeV1_0_to_V1_1.t.sol`
- Documentación de upgrade: `test/v1.1/README_UpgradeV1_0_to_V1_1.md`
- Storage layout: Ver comentarios en `src/BTContracts/v1.1/BTtokensEngine_v1.sol` línea 575+
