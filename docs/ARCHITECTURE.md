# Arquitectura: Engine, Tokens y Access Manager

Este documento describe la relación entre el **BTtokensEngine**, los **BTtokens** y los **BTtokensManager**, el orden de deployment y las funcionalidades de cada contrato.

---

## 1. Visión general

- **BTtokensEngine**: Contrato central que crea y administra todos los tokens. Es el único que puede desplegar nuevos tokens y gestionar blacklist, pause y roles.
- **BTtokensManager**: Contratos de acceso que asignan roles (minter, burner) a agentes y definen qué direcciones pueden llamar mint/burn en qué tokens.
- **BTtokens**: ERC20 desplegados por el engine mediante proxies. Cada token está ligado a un engine y a un access manager.

**Aislamiento de agentes**: Los agentes asignados en un Access Manager **solo pueden** mintear/quemar en los tokens que usan ese manager. Un agente del Manager A no puede mintear en un token que usa el Manager B.

---

## 2. Orden de deployment

1. **Engine** (y su proxy, si aplica)  
   - Se inicializa con: owner, implementación del token, y el **Access Manager por defecto de BoulderTech** (`s_boulderAccessManagerAddress`).

2. **Access Managers**  
   - **BoulderTech**: manager por defecto, compartido por tokens que no tienen uno específico.  
   - **Por grupo/cliente**: managers adicionales para aislar agentes (p. ej. un manager por grupo de deals).  
   - Cada BTtokensManager se construye con un `initialAdmin`; típicamente se le da `ADMIN_ROLE` al engine para que pueda asignar roles.

3. **Tokens**  
   - Solo el engine puede desplegar tokens mediante `createToken`.  
   - En cada creación se indica qué access manager usará ese token (via `data`).

---

## 3. Flujo de datos entre contratos

```
                    ┌─────────────────┐
                    │  BTtokensEngine │
                    │   (onlyOwner)   │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
  createToken()    assignMinterRole()    changeTokenAccessManager()
         │         assignBurnerRole()              │
         │                   │                     │
         ▼                   ▼                     ▼
  ┌─────────────┐    ┌─────────────────┐    ┌─────────────┐
  │ BTtokens    │◄───│ BTtokensManager │    │ BTtokens    │
  │ (proxy)     │    │ (grantRole,     │───►│ setAccess   │
  │             │    │  setTargetFunc) │    │ Manager     │
  └──────┬──────┘    └─────────────────┘    └─────────────┘
         │
         │  Cuando alguien llama mint() o burn(), el modifier
         │  restricted del token consulta al manager:
         │  "¿este msg.sender tiene permiso para esta función?"
         ▼
  ┌─────────────────┐
  │ BTtokensManager │
  └─────────────────┘
```

- **Engine → Token**: crea el proxy, llama `setNameAndSymbol`, `setAccessManager`.  
- **Engine → Manager**: `grantRole`, `setTargetFunctionRole` para configurar quién puede mint/burn en cada token.  
- **Token → Engine**: `isBlacklisted()`, `isEnginePaused()` (para modifiers).  
- **Token → Manager**: el modifier `restricted` consulta el manager actual para permitir/denegar mint y burn.

---

## 4. Manager por defecto vs manager por token

- **`s_boulderAccessManagerAddress`**: manager por defecto de BoulderTech. Se fija en `initialize` y **no se modifica**.  
- **`s_accessManagerForDeployedTokens[key]`**: mapping que guarda qué manager usa cada token.  
- Si un token usa el manager de BoulderTech, sus agentes pueden operar sobre todos los tokens que usen ese mismo manager.  
- Si un token usa un manager distinto (p. ej. de un grupo), solo los agentes de ese manager pueden mintear/quemar ese token; los agentes del manager de BoulderTech no pueden.

El engine emite `AccessManagerSet` cuando se crea un token cuyo manager **no** es el de BoulderTech, para que off-chain se pueda distinguir tokens con manager custom.

---

## 5. Diseños importantes

### 5.1 Data opaca en createToken

`createToken` recibe `bytes memory data` y la pasa al token sin decodificarla. El engine obtiene el manager con `token.s_manager()` tras la inicialización. Así, si cambia el formato de `data` en el token, no hace falta tocar el engine.

### 5.2 Token como fuente de verdad del manager

El manager actual se obtiene siempre del token (p. ej. `assignMinterRole` usa `_getManagerAddressForDeployedToken`, que llama a `token.s_manager()`). Así se evita desincronización si el manager cambia.

### 5.3 setAccessManager solo vía engine

`setAccessManager` en el token tiene modifier `onlyEngine`. Solo el engine puede cambiarlo, y lo hace a través de `changeTokenAccessManager`, que además actualiza `s_accessManagerForDeployedTokens`. El owner del token no puede cambiar el manager por su cuenta.

### 5.4 Migración al cambiar nombre/símbolo

En `changeTokenNameAndSymbol`, el engine conserva el manager del token al actualizar el mapping (lee `s_accessManagerForDeployedTokens[key]` antes de `_removeToken` y lo asigna al nuevo key).

---

## 6. Funcionalidades por contrato

### BTtokensEngine

| Función | Descripción |
|--------|-------------|
| `initialize` | Inicializa el engine con owner, implementación del token y manager por defecto de BoulderTech. |
| `createToken` | Despliega un nuevo token proxy. Requiere `data`, `tokenName`, `tokenSymbol`, `tokenAgent`, `tokenOwner`. Asigna minter/burner en el manager del token. |
| `setNewTokenImplementationAddress` | Actualiza la implementación usada para nuevos tokens (con engine pausado). |
| `changeTokenNameAndSymbol` | Cambia nombre y símbolo de un token desplegado. |
| `changeTokenAccessManager` | Cambia el access manager de un token. Hay que reasignar roles en el nuevo manager después. |
| `blacklist` / `batchBlacklist` | Añade direcciones a la blacklist global. |
| `unBlacklist` / `batchUnblacklist` | Quita direcciones de la blacklist. |
| `assignMinterRole` | Da rol minter a un agente en el manager del token indicado. |
| `assignBurnerRole` | Da rol burner a un agente en el manager del token indicado. |
| `pauseEngine` / `unPauseEngine` | Pausa o reactiva el engine (afecta mint, transfer, approve, etc.). |
| `getDeployedTokenProxyAddress` | Devuelve el proxy de un token por su key. |
| `getDeployedTokensKeys` | Lista todos los keys de tokens desplegados. |
| `getAccessManagerForDeployedToken` | Devuelve el access manager de un token por su key. |
| `isBlacklisted` | Indica si una dirección está en la blacklist. |
| `isEnginePaused` | Indica si el engine está pausado. |

### BTtokens (implementación)

| Función | Descripción |
|--------|-------------|
| `initialize` | Inicializa el token con `data` (engine, manager, owner, holder, name, symbol, decimals). |
| `mint` | Mintea a una cuenta. Requiere engine no pausado, cuenta no blacklisteada y permiso del manager (`restricted`). |
| `burn` | Quema de una cuenta. Solo para `s_token_holder` o cuentas blacklisteadas. Requiere permiso del manager (`restricted`). |
| `approve` | Aprueba un spender. Engine no pausado y no blacklisted. |
| `transfer` / `transferFrom` | Transferencias. Engine no pausado y no blacklisted. |
| `permitAndTransfer` | Permiso EIP-2612 y transfer en una sola tx. |
| `setNameAndSymbol` | Cambia nombre y símbolo. Solo engine. |
| `setTokenHolder` | Cambia `s_token_holder`. Solo owner. |
| `setAccessManager` | Cambia el access manager. Solo engine; actualiza `s_manager` y `_setAuthority`. |
| `name` / `symbol` / `decimals` | Getters ERC20 estándar. |
| `manager` / `engine` | Devuelven el manager y el engine del token. |

### BTtokensManager

| Función | Descripción |
|--------|-------------|
| Constructor | Recibe `initialAdmin`. Asigna `ADMIN_ROLE` a ese admin (típicamente el engine). |
| `grantRole` | Heredado de AccessManager. Otorga roles a direcciones. |
| `setTargetFunctionRole` | Heredado. Define qué rol puede llamar qué función en qué contrato (p. ej. mint/burn en un token). |
| `revokeRole` / `hasRole` | Heredados. Gestión y consulta de roles. |

El engine usa `grantRole(AGENT, agent, 0)` y `setTargetFunctionRole(tokenProxy, [mint|burn], AGENT)` para configurar quién puede mintear y quemar en cada token.

---

## 7. Eventos relevantes

| Evento | Contrato | Cuándo |
|--------|----------|--------|
| `TokenCreated` | Engine | Nuevo token desplegado. |
| `AccessManagerSet` | Engine | Token creado con manager distinto al de BoulderTech. |
| `AccessManagerChanged` | Engine | Se cambió el manager de un token. |
| `MinterRoleSet` / `BurnerRoleSet` | Engine | Se asignó rol minter/burner a un agente. |
| `Blacklisted` / `UnBlacklisted` | Engine | Cambios en la blacklist. |
| `EnginePaused` / `EngineUnpaused` | Engine | Pausa del engine. |
| `TokenNameAndSymbolChanged` | Engine | Cambio de nombre/símbolo de un token. |
