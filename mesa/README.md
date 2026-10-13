# Mesa: protótipo visual

Interface completa da mesa de RPG com mestre IA, feita em **Godot 4.7.2 com GDScript** (também roda no 4.3).
Todos os painéis funcionam com dados de exemplo e um combate jogável. A IA e o
modelo próprio ainda não estão conectados: o mestre usa falas pré-escritas.

## Como abrir

1. Baixe o Godot 4.7.2 (versão padrão, não a .NET): https://godotengine.org/download/archive/4.7.2-stable/
   Todo o grupo deve usar a mesma versão: um projeto salvo numa versão nova pode não abrir numa antiga.
2. Abra o Godot, clique em **Importar** e escolha o arquivo `project.godot` desta pasta.
3. Aperte **F5** para jogar.

Na primeira abertura o Godot importa fontes e scripts; leva alguns segundos.

## O que já funciona

| Região | O que tem |
| --- | --- |
| Grupo (esquerda) | Retrato, classe, PV e recurso animados, destaque da vez, ícones de condição com duração |
| Ficha (clique no retrato) | Abas Status e atributos, Pontos de upgrade, Perfil e biografia, Inventário e magias |
| Mapa (centro) | Cena com pins, tokens, mira de alvo único e de área, zonas perto/médio, dano e cura flutuantes |
| Mestre (direita) | Avatar com 4 humores, narração, balão de provocação, histórico de dados clicável, decisões do motor |
| Barra de ações | Texto livre, pedido de teste do mestre, atalhos de habilidade, rolagem livre, encerrar turno |
| Diário | Missões com objetivos e bíblia rápida com busca |
| Modo streamer | Esconde controles e decisões do motor, mostra legenda grande sobre o mapa |

Experimente escrever no campo de texto: "quero me esconder", "vou escalar a parede",
"tento convencer o goblin". O mestre provisório pede o teste certo.

## Atalhos

| Tecla | Ação |
| --- | --- |
| 1 a 5 | Usar habilidade |
| Enter | Ir para o campo de texto |
| C | Abrir a ficha de quem joga |
| J | Abrir ou fechar o diário |
| F8 | Modo streamer |
| Esc | Fechar ficha, diário ou cancelar mira |
| Botão direito | Cancelar mira |

## Estrutura

```
data/                  dados de exemplo (JSON) — personagens, inimigos, condições, missões, falas
scripts/core/
  rules_engine.gd      motor de regras: único lugar que rola dados
  game_state.gd        estado da mesa e sinais (autoload "Game")
  master_mock.gd       mestre provisório com falas por evento (autoload "Master")
scripts/ui/            um script por painel; main.gd monta a tela
scripts/dev/           ferramenta de prints e teste automático
assets/fonts/          Alegreya e Alegreya Sans (licença OFL, arquivos inclusos)
assets/art/            pasta para a arte do grupo (veja abaixo)
```

Regra da arquitetura: **a interface nunca altera o estado direto**. Ela chama funções do
`Game` e escuta os sinais. Quando o modelo de IA entrar, só o `master_mock.gd` é trocado.

## Trocando os placeholders pela arte do grupo

Basta salvar os arquivos com estes nomes; o jogo usa a arte automaticamente se ela existir.

| Arte | Arquivo | Formato sugerido |
| --- | --- | --- |
| Retrato de personagem ou inimigo | `assets/art/portraits/<id>.png` (ex.: `lia.png`, `gob_a.png`) | quadrado, 256×256 |
| Avatar do mestre | `assets/art/master/<humor>.png` (`neutro`, `satisfeito`, `irritado`, `entediado`) | quadrado, 256×256 |
| Cena do mapa | `assets/art/scenes/<background>.png` (ex.: `mina_galeria.png`) | 16:9, 1920×1080 |
| Ícone de condição | `assets/art/conditions/<id>.png` (ex.: `envenenado.png`) | quadrado, 64×64 |

Os ids estão nos arquivos de `data/`.

## Cores e o que significam

| Cor | Uso |
| --- | --- |
| Violeta | Só provocações do mestre. Nunca regra. |
| Âmbar | Dados, críticos e a vez de quem joga |
| Vermelho / azul | PV / recurso |
| Papel | Tudo que pertence a um personagem (ficha, diário) |

## Ferramentas de teste

Prints de todas as telas (pasta de saída à escolha):

```
godot --path . -- --shots=/tmp/prints
```

Combate jogado sozinho até o fim, para pegar erros na resolução de ações:

```
godot --path . -- --autoplay
```

## Gerar o executável

No Godot: **Editor > Gerenciar modelos de exportação > Baixar**, depois
**Projeto > Exportar > Adicionar > Windows Desktop > Exportar projeto**.

## Próximos passos (roadmap do documento)

1. Trocar `master_mock.gd` pelo modelo local (NobodyWho + llama.cpp) mantendo os mesmos sinais.
2. Multiplayer: modo anfitrião no executável, os outros conectam.
3. Criador de classes por descrição, com validador de orçamento de poder.
4. Salvar e retomar campanha.
