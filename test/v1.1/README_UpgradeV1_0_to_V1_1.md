# Test: Upgrade v1.0 → v1.1 (Engine + Token)

Este documento describe el test `UpgradeV1_0_to_V1_1.t.sol`, que valida el **upgrade en producción** desde la stack v1.0 (engine + token) a la v1.1, y la funcionalidad nueva de **cambio de access manager por token**.

---

## Objetivo

- Simular un deploy en v1.0 (como en producción hoy).
- Hacer upgrade del **engine** a v1.1 y del **token** a v1.1.
- Comprobar que el estado se preserva y que las funciones nuevas de v1.1 (p. ej. `changeTokenAccessManager`) funcionan.

---

## Flujo general (qué hace el test)

1. **Deploy v1.0**  
   Se usa `DeployEngine` (script actual): despliega **proxy del engine** con implementación v1.0, implementación del **token** v1.0 y un **BTtokensManager**. El test es el `owner` del engine (`address(this)`).

2. **Inicialización**  
   - El admin (`initialAdmin`) le da al engine el rol `ADMIN_ROLE` en el manager.  
   - Se llama `engine.initialize(owner, tokenImpl, accessManager)` (todo v1.0).

3. **Crear un token**  
   - `engine.createToken(name, symbol, data, agent, tokenOwner)`.  
   - El token se despliega con **implementación v1.0** y queda registrado en el engine.  
   - `data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenHolder, name, symbol, decimals)`.

4. **Upgrade del engine a v1.1**  
   - Solo **owner** del engine y con engine **pausado**.  
   - `engine.pauseEngine()` → `engine.upgradeToAndCall(engineV1_1Implementation, "")` → `engine.unPauseEngine()`.

5. **Upgrade del token a v1.1**  
   - El token es UUPS: quien hace el upgrade es el **owner del token** (`tokenOwner`), y solo si el **engine está pausado**.  
   - `engine.pauseEngine()` → (como `initialAdmin` = token owner) `token.upgradeToAndCall(tokenV1_1Implementation, "")` → `engine.unPauseEngine()`.  
   - Sin este paso, el token no tiene `setAccessManager` y `changeTokenAccessManager` del engine no podría actualizar el manager del token.

6. **Comprobaciones**  
   - Versión engine/token, estado del engine, token sigue en `s_deployedTokens`, datos del token, y (en el test dedicado) `changeTokenAccessManager` + `getAccessManagerForDeployedToken`.

---

## Tests incluidos

| Test | Qué valida |
|------|------------|
| `test_UpgradeV1_0_to_V1_1_StatePreservedAndV1_1Works` | Flujo completo: crear token v1.0 → upgrade engine → upgrade token → que engine y token reporten v1.1, estado correcto, token usable y que `getAccessManagerForDeployedToken(salt)` sea `0` (token creado en v1.0 no estaba en ese mapping). |
| `test_UpgradeV1_0_to_V1_1_RequiresPaused` | Que no se pueda hacer upgrade del engine sin antes pausar (`BTtokensEngine__EngineNotPaused`). |
| `test_UpgradeV1_0_to_V1_1_OnlyOwner` | Que solo el owner del engine pueda llamar `upgradeToAndCall` en el engine (`OwnableUnauthorizedAccount`). |
| `test_UpgradeV1_0_to_V1_1_ChangeTokenAccessManager` | Tras upgrade completo: llamar `engine.changeTokenAccessManager(token, newManager)`, y comprobar que el token tiene `s_manager() == newManager` y que `getAccessManagerForDeployedToken(salt)` devuelve el nuevo manager. |

---

## Imports y roles

- **Engine v1.0 / v1.1**: `EngineV1_0` y `EngineV1_1` (alias del mismo nombre de contrato en carpetas distintas).  
- **Token v1.0 / v1.1**: `TokenV1_0` y `TokenV1_1`.  
- **Manager**: `BTtokensManager` (v1.0), compartido; en v1.1 la lógica de “qué manager usa cada token” está en el engine con `s_accessManagerForDeployedTokens` y `changeTokenAccessManager`.  
- **Owner del engine**: `address(this)` (el contrato de test).  
- **Token owner**: `initialAdmin`; es quien debe llamar `token.upgradeToAndCall(...)` para subir el token a v1.1.

---

## Storage layout (importante)

En Solidity el storage es por **slots**: el orden de las variables de estado fija el slot. Si en v1.1 se añaden variables “en el medio” respecto a v1.0, el proxy del engine leería slots equivocados y el estado se corrompería.

En v1.1 las variables nuevas (p. ej. `s_accessManagerForDeployedTokens`) están añadidas **al final**, usando espacio del `__gap` de v1.0, para no desplazar los slots existentes. Este test asume que ese layout se respeta; si se toca el orden de las state vars en engine o token, hay que revisar compatibilidad antes de hacer upgrade en test/producción.

---

## Cómo ejecutar

```bash
# Todos los tests del contrato de upgrade
forge test --match-contract "UpgradeV1_0_to_V1_1" -vvv

# Un test concreto
forge test --match-test "test_UpgradeV1_0_to_V1_1_ChangeTokenAccessManager" -vvv
```

---

## Resumen para retomar

- **Qué prueba**: upgrade realista v1.0 → v1.1 (engine y token) y la función v1.1 `changeTokenAccessManager`.
- **Por qué upgrade del token**: el token v1.1 expone `setAccessManager(onlyEngine)`; el engine v1.1 lo usa en `changeTokenAccessManager`. Sin upgrade del token, esa función no podría cambiar el manager del token.
- **Quién hace cada upgrade**: engine → owner del engine (test); token → owner del token (`initialAdmin`), con engine pausado.
- **Dónde mirar el código**: `test/v1.1/UpgradeV1_0_to_V1_1.t.sol` y este README en `test/v1.1/README_UpgradeV1_0_to_V1_1.md`.
