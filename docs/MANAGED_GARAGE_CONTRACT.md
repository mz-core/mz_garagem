# Contrato de garagens administradas

## Autoridade e escopo

`mz_garagem` e a unica autoridade das definicoes persistentes de garagem. O `mz_admin` apenas coleta os dados do assistente e chama o export oficial; nenhuma definicao e gravada em `mz_orgs.config_json`.

Esta primeira entrega permite somente criar:

- garagem `public`;
- garagem `org`, vinculada a uma organizacao ativa do `mz_core`.

O mesmo contrato permite listar, editar, reposicionar, arquivar e reativar essas definicoes. Exclusao, multiplos spawns, frotas de servico e garagens residenciais administradas nao fazem parte deste lote.

## Persistencia

A inicializacao executa somente `CREATE TABLE IF NOT EXISTS mz_garage_definitions`. Nao existe `DROP`, `DELETE`, alteracao destrutiva ou migration de dados existentes.

Cada linha guarda codigo estrutural unico, label, tipo, `org_code` opcional, definicao normalizada em JSON, estado ativo, autor e timestamps.

As definicoes de `shared/garages.lua` continuam validas. Um codigo estatico sempre tem precedencia; uma linha persistente que colida com ele e ignorada no bootstrap.

## Exports servidor

```lua
local ready, detail = exports['mz_garagem']:IsManagedGarageReady()

local ok, garageOrError = exports['mz_garagem']:CreateManagedGarage(source, {
  code = 'mafia_sede',
  label = 'Garagem da Mafia',
  kind = 'org',
  orgCode = 'mafia',
  entry = { x = 0.0, y = 0.0, z = 0.0 },
  spawn = { x = 2.0, y = 0.0, z = 0.0, w = 90.0 },
  store = { x = -2.0, y = 0.0, z = 0.0 },
  settings = {
    categoryMode = 'car',
    strictGarage = true,
    blipEnabled = false,
    allowImpounded = false,
    requireDuty = false,
    primaryOnly = false,
    minGradeLevel = 0
  }
})

local definitions = exports['mz_garagem']:ListManagedGarages()

local ok, definitionsOrError = exports['mz_garagem']:ListManagedGaragesForAdmin(source)
local ok, updatedOrError = exports['mz_garagem']:UpdateManagedGarage(source, 'mafia_sede', payload)
local ok, stateOrError = exports['mz_garagem']:SetManagedGarageActive(source, 'mafia_sede', false)
```

`CreateManagedGarage` exige um `source` online com a permissao global `staff.garages.create`. O proprio `mz_garagem` revalida a permissao com `mz_core:HasGlobalPermission`; validacao feita pelo chamador nao e considerada autoridade.

`ListManagedGaragesForAdmin` exige `staff.garages.view`. Edicao e ciclo de vida exigem `staff.garages.manage`. Para administrar pela interface, conceda `view` junto de `manage`.

O nome de exibicao e opcional. Vazio gera `Garagem Pública` para tipo `public` e `Garagem - <nome da organização>` para tipo `org`. O mesmo label e usado no cabecalho e no blip.

Codigo estrutural, tipo e organizacao vinculada sao imutaveis depois da criacao. Edicao aceita nome, categoria, modo de vagas, blip, regras de acesso e os tres pontos.

Arquivamento apenas define `active=0` e remove a garagem do runtime dos clients. Reativacao valida novamente JSON, coordenadas e organizacao ativa antes de registrar os pontos. Nao existe exclusao pelo menu ou pelos exports deste lote.

## Validacao fail-closed

A criacao e recusada quando:

- o repositorio nao terminou de inicializar;
- `mz_core` ou a consulta de permissao falha;
- o player nao esta carregado;
- existem campos de topo fora da allowlist;
- codigo, label, tipo, categoria ou nivel minimo sao invalidos;
- o codigo colide com definicao estatica ou persistente;
- a organizacao nao existe ou esta arquivada;
- uma garagem publica recebe `orgCode`;
- faltam entrada, spawn ou armazenamento;
- coordenadas nao sao finitas ou saem dos limites seguros;
- spawn ou armazenamento ficam a mais de 250 metros da entrada.
- uma edicao tenta trocar codigo, tipo ou organizacao.

Tipos aceitos em `categoryMode`: `car`, `bike`, `car_bike`, `boat` e `plane`.

## Regras geradas

- modo estrito: `strict_garage=true` e `shared_pool=false`;
- modo compartilhado: `strict_garage=false` e `shared_pool=true`;
- garagem organizacional sempre exige membership;
- duty, organizacao primaria e nivel minimo sao opcionais e revalidados pelo fluxo normal de acesso;
- apreendidos sao desabilitados em garagem organizacional nesta entrega;
- marker, texto, blip e raios usam defaults fixos do servidor.

Depois do insert, a definicao entra em `MZGaragemGarages` no servidor e e enviada aos clients. Os clients normalizam os vetores e reconstroem pontos do `mz_interact` ou blips/markers legados. A criacao tambem usa o export oficial `mz_core:CreateDetailedLog`.

No assistente do `mz_admin`, o modo de posicionamento fecha o foco NUI sem descartar o rascunho. O Staff pode andar ou dirigir, usa `G` para travar/destravar o proprio ped ou o veiculo que estiver dirigindo, `E` para capturar cada ponto e `X` para cancelar. A captura destrava automaticamente antes da proxima etapa. Ao concluir, cancelar ou parar o resource, qualquer trava criada pelo assistente e removida e o menu do rascunho e reaberto quando aplicavel.

O assistente preserva um estado de congelamento que ja existia antes dele. Passageiros nao podem congelar o veiculo; devem ocupar o banco do motorista.

## Compatibilidade

- nenhuma garagem estatica foi removida ou alterada;
- callbacks existentes de abrir, retirar, guardar, apreensao e rollback foram preservados;
- exports de garagem residencial foram preservados;
- `public`, `org`, `service` e `house` continuam usando o mesmo resolvedor de acesso;
- indisponibilidade da persistencia nova nao transforma uma negacao em permissao.
