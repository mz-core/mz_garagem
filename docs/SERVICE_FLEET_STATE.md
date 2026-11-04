# Estado persistente da frota de servico

## Escopo

A frota de servico (`kind = "service"`) continua usando o runtime efemero de
`mz_garagem` para retirada, confirmacao de entidade e devolucao. Este lote
adiciona somente a persistencia da condicao da viatura por jogador.

Cada linha e identificada por:

- `citizenid` do personagem que retirou;
- `garage_id` da garagem de servico;
- `entry_id` da entrada da frota (`police_cruiser`, `police_maverick`, ...).

O `fleet_id` tambem e gravado para diagnostico e integridade.

## Persistencia

A tabela e criada de forma nao destrutiva no bootstrap:

```sql
CREATE TABLE IF NOT EXISTS mz_garage_service_state (
  citizenid VARCHAR(64) NOT NULL,
  garage_id VARCHAR(64) NOT NULL,
  fleet_id VARCHAR(64) NOT NULL,
  entry_id VARCHAR(64) NOT NULL,
  fuel FLOAT NOT NULL DEFAULT 100,
  engine FLOAT NOT NULL DEFAULT 1000,
  body FLOAT NOT NULL DEFAULT 1000,
  props_json LONGTEXT NULL,
  destroyed TINYINT(1) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (citizenid, garage_id, entry_id),
  KEY idx_mz_garage_service_state_fleet (garage_id, fleet_id, entry_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

O `mz_garagem` e o owner desta tabela. `mz_vehicles` continua sendo o owner dos
veiculos persistentes (`owner_type = "player"` ou `"org"`); esta tabela guarda
somente a condicao de unidades temporarias da frota de servico.

## Fluxo

1. Na retirada, `MZGaragemService.withdraw` procura o estado do jogador para
   `garage_id + entry_id`. Se existir, usa `fuel`, `engine`, `body`, `props` e
   `destroyed` salvos. Se nao existir, usa os defaults de
   `shared/service_fleet.lua`.
2. Na devolucao validada, `MZGaragemService.store` grava o estado antes de
   remover o runtime. Apenas payloads que passaram por runtime, placa, entidade,
   modelo, bucket e garagem chegam a esta etapa.
3. A lista da garagem mostra o estado salvo do jogador quando a entrada nao esta
   ativa naquele momento.
4. O cache em memoria e carregado por `citizenid` na primeira consulta e
   atualizado na devolucao. `resetAll` limpa o cache em restart/testes.

## Configuracao

Em `shared/config.lua`:

```lua
MZGaragemConfig.service.persist_state = true
```

Com `false`, a frota volta ao comportamento anterior: cada retirada usa os
valores de `service_fleet.lua` e nada e gravado.

## Falha de banco

A devolucao nao e bloqueada se a gravacao do estado falhar. O runtime e removido,
o cache local e atualizado e o erro e registrado no console. A proxima consulta
em um novo processo usa os defaults ate a persistencia voltar a funcionar.

## Diferenca em relacao ao VRP

O VRP grava `motor`, `lataria` e `gasolina` em `vrp_user_veiculos_service` por
`user_id`. Este contrato faz o equivalente por `citizenid`, mas sem criar uma
copia de cada veiculo por jogador: a entrada da frota e a mesma, e o estado e
por personagem + garagem + entrada.

## Validacao de runtime

- [ ] Retirar, danificar, guardar e retirar novamente: condicao preservada.
- [ ] Outro personagem retira a mesma entrada: recebe os defaults ou o estado dele.
- [ ] Reiniciar `mz_garagem`: estado e recarregado do banco.
- [ ] `persist_state=false`: retirada sempre usa os defaults da frota.
- [ ] Falha simulada de banco nao impede a devolucao da viatura.
