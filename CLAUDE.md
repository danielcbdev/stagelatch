# stagelatch

Quality gate *change-aware* para repositórios Flutter/Dart. Um único motor com dois pontos de entrada:

- **Hook local:** pre-commit e pre-push.
- **CI:** pull request.

Avalia o snapshot exato que está sendo publicado (o **index** no pre-commit, o commit enviado no pre-push, o HEAD do PR no CI), com semântica Dart e só no escopo afetado.

Distribuído como CLI no pub.dev (`dart pub global activate stagelatch`). Projeto de portfólio: qualidade de engenharia, decisões documentadas e casos de borda resolvidos importam mais que quantidade de features.

## Idioma

- Conversa comigo: português, direto, sem introduções.
- Em inglês: código, identificadores, comentários, mensagens de commit, README, CHANGELOG, docs públicas e mensagens do CLI.

## Decisões fixas (ADRs a registrar em `docs/adr/`)

1. **Validar o index, não o working tree.**
   - Blobs lidos por um processo `git cat-file --batch` persistente: um spawn, não um por arquivo.
   - Análise com `package:analyzer` + `OverlayResourceProvider`.
   - O overlay recebe a versão do index de **todo** arquivo que diverge entre index e working tree (`git diff --name-only -z`), não só dos staged. Sem isso, mudanças não staged contaminam a análise.
   - Nunca usar stash.
2. **Autofix seguro.**
   - Grava o blob corrigido no index (`git hash-object -w --stdin` + `git update-index --cacheinfo <mode>,<sha>,<path>`).
   - Só reescreve o arquivo no disco se ele não tiver mudanças unstaged.
3. **Determinístico. Nenhuma IA no caminho de bloqueio.**
   - Sem rede.
   - Mesmo input, mesmo resultado em qualquer máquina e no CI.
   - O orçamento de tempo só **avisa** quando estoura. Nunca pula nem encurta um check, porque isso faria o veredito depender da máquina.
4. **Distribuição via `pub global activate`, nunca como dev_dependency.** O `analyzer` entraria no version solving do projeto e conflitaria com freezed, json_serializable e build_runner.
5. **Mesmo motor para hook e CI.**
   - O hook local é feedback rápido.
   - A garantia é o `stagelatch ci` no pull request.
6. **Hooks são gatilhos finos, sem lógica.** A única lógica permitida é localizar o executável. Se ele não estiver instalado, o hook avisa e **não bloqueia**, porque o CI é a garantia:
   ```sh
   #!/bin/sh
   # stagelatch:managed
   if command -v stagelatch >/dev/null 2>&1; then
     exec stagelatch run pre-commit "$@"
   elif command -v stagelatch.bat >/dev/null 2>&1; then
     exec stagelatch.bat run pre-commit "$@"
   elif command -v dart >/dev/null 2>&1 &&
     dart pub global list 2>/dev/null | grep -q '^stagelatch '; then
     exec dart pub global run stagelatch run pre-commit "$@"
   fi
   echo "stagelatch not found; skipping. Install: dart pub global activate stagelatch" >&2
   exit 0
   ```
   Os dois fallbacks existem por causa do Windows (ver riscos). A forma final do template é a que passar no teste de aceitação do runner Windows.
7. **Snapshot e changeset por ponto de entrada.**

   | Entrada | Snapshot | Changeset |
   |---|---|---|
   | pre-commit | index | index vs HEAD (primeiro commit: vs árvore vazia) |
   | pre-push | commit enviado, lido da stdin do hook (`<local ref> <local sha> <remote ref> <remote sha>`) | `<remote sha>..<local sha>` |
   | `ci` | HEAD do PR | `merge-base(--base, HEAD)..HEAD` |

   - O overlay segue a mesma regra da decisão 1: versão do snapshot para todo arquivo que diverge do working tree.
   - **Pre-push de branch novo** (`<remote sha>` zerado): a base é o merge-base com o branch padrão do remoto. Remoção de branch (`<local sha>` zerado) não tem o que validar.
   - **Merge em andamento** (`MERGE_HEAD` existe): o changeset é só o que difere de **ambos** os pais, isto é, resoluções de conflito e edições manuais. O que veio intacto do outro branch já passou pelo CI dele.
   - **Rebase em andamento:** quando o hook dispara, usa o changeset normal (index vs HEAD).
   - **Clone raso no CI** sem merge-base alcançável: falha com mensagem clara pedindo `fetch-depth: 0`. Nunca analisa um diff errado.
8. **Paridade com o SDK do projeto.**
   - `format` e `analyze` devem dar o mesmo resultado que o `dart format` e o `dart analyze` do SDK que o time usa. Divergência é bug.
   - Resolução do SDK, nesta ordem: `sdk_path` da config, FVM (`.fvmrc`, `.fvm/flutter_sdk`), `dart` no PATH.
   - O mecanismo (bibliotecas embutidas ou delegar ao SDK resolvido) é decidido no spike, com teste de paridade.
   - Plugins do analyzer e `custom_lint` não rodam in-process. É limitação documentada, não bug.
9. **Um vocabulário só: o ID de regra.**
   - `<check>/<rule>` é a única notação, usada em hooks, `rules:`, ignore, baseline e reporters.
   - A lista de um hook aceita `<check>` (todas as regras do check) ou `<check>/<rule>`.
   - Severidade se configura só no mapa `rules:` (`error`, `warning`, `off`). As seções por check guardam apenas parâmetros.
10. **Supressão explícita e localizada.**
    - Comentário `// stagelatch:ignore <rule-id>` em Dart e `# stagelatch:ignore <rule-id>` em YAML, na linha do finding ou na anterior. O ID é obrigatório; não existe ignore genérico.
    - `exclude` por glob na config, para caminhos inteiros.
    - O `analyze` respeita os `// ignore:` e o `analysis_options.yaml` do próprio analyzer.
11. **Nunca interativo sem TTY.**
    - Nenhum comando abre prompt quando stdin ou stdout não é um TTY; o `init` segue com os padrões detectados.
    - Saída sem cor fora de TTY e quando `NO_COLOR` está definido.
    - Motivo: hooks, CI e agentes de IA travam em qualquer pergunta interativa.

## Arquitetura

```
lib/src/
├── domain/          # Check, Finding, Severity, Location, ChangeSet, Fix — sem dependência de git/analyzer/IO
├── application/     # Pipeline, seleção de checks por hook, scheduler, orçamento de tempo, Baseline, ConfigLoader
├── infrastructure/  # GitClient, AnalyzerWorkspace, DartStyleFormatter, PubspecReader, SdkLocator, reporters, HookInstaller
└── cli/             # comandos (package:args CommandRunner)
```

- Checks recebem um `CheckContext` (leitura de blobs, sessão do analyzer, pubspec parseado, config) e retornam findings. Não conhecem git, analyzer nem IO diretamente.
- IDs de regra no formato `<check>/<rule>`, por exemplo `pubspec/path-dependency`. São estáveis, documentados e usados em config, ignore e baseline.
- Fingerprint do baseline: `ruleId + path + hash do trecho normalizado`. Nunca número de linha.
- Locations com linha e coluna. YAML lido com `package:yaml` preservando os source spans.
- Descoberta de pacote: cada arquivo pertence ao `pubspec.yaml` mais próximo acima dele, com um contexto de análise por pacote. Pub workspaces só na `0.3.0`.
- `HookInstaller`:
  - resolve o diretório de hooks com `git rev-parse --git-path hooks`, que já considera o `core.hooksPath` (husky e lefthook o alteram) e os worktrees ligados, onde os hooks ficam no repositório principal;
  - não sobrescreve hooks de terceiros sem `--force`, e faz backup quando sobrescreve;
  - no `uninstall`, remove só hooks marcados com `stagelatch:managed` e restaura o backup, se houver.

## CLI

| Comando | Função | Desde |
|---|---|---|
| `stagelatch init` | detecta stack, gera `stagelatch.yaml`, instala hooks | `0.1.0-dev.1` |
| `stagelatch install` | só instala hooks (por clone) | `0.1.0-dev.1` |
| `stagelatch uninstall` | remove os hooks gerenciados e restaura backups | `0.1.0-dev.1` |
| `stagelatch run <hook>` | executa os checks do hook sobre o snapshot dele (decisão 7) | `pre-commit` na `0.1.0-dev.1`, `pre-push` na `0.1.0` |
| `stagelatch ci --base <ref> --reporter <console\|json\|github\|junit\|sarif>` | mesmo motor sobre o diff do PR | `0.1.0` |
| `stagelatch doctor` | diagnostica hooks, `core.hooksPath`, SDK resolvido, PATH e `min_version` | `0.1.0` |
| `stagelatch baseline create\|prune` | adoção em projeto legado | `0.2.0` |
| `stagelatch why <test-file>` | explica a seleção de teste afetado | `0.3.0` |

`run` e `ci` aceitam `--all` (desde a `0.2.0`), que ignora o changeset e varre o snapshot inteiro. É o que o `baseline create` usa.

`run` e `ci` aceitam `--reporter json` (desde a `0.1.0`): a lista de findings com regra, severidade, caminho, linha, coluna, mensagem e fix aplicado, mais o tempo de cada check. É a saída para scripts e agentes de IA, que não devem interpretar texto de terminal.

Exit codes:

| Código | Significado |
|---|---|
| `0` | passou |
| `1` | findings bloqueantes |
| `64` | uso incorreto |
| `70` | erro interno |
| `78` | config inválida |

## Config (`stagelatch.yaml`)

```yaml
min_version: 0.1.0

hooks:
  pre-commit: [format, analyze, codegen, pubspec, l10n, assets, sensitive-files, tests/solo, tests/new-skip]
  pre-push: [analyze, tests/affected]

# Severity per rule: error | warning | off. Omitted rules keep their default.
rules:
  l10n/unused-key: warning
  tests/new-skip: warning
  pubspec/unpinned-git: off

# Paths that never produce findings.
exclude: [lib/generated/**]

# Optional. Default resolution: FVM, then `dart` on PATH.
# sdk_path: .fvm/flutter_sdk

# Reported when exceeded. Never skips a check.
time_budget: 2s

format:
  fix: true

analyze:
  scope: affected
  fail_on: [error, warning]

codegen:
  generated_files_committed: true

pubspec:
  monotonic_build_number: [release/*]

assets:
  max_file_size: 500KB
  ignore: [assets/videos/**]

baseline: .stagelatch/baseline.json
```

O schema é publicado como JSON Schema (`0.2.0`) para autocomplete no editor.

## Catálogo de regras

| Check | Regras |
|---|---|
| `format` | `unformatted` |
| `analyze` | código do diagnóstico do analyzer |
| `codegen` | `stale`: diff de AST HEAD vs index das declarações anotadas sem o `.g.dart`/`.freezed.dart` correspondente staged |
| `pubspec` | `path-dependency`, `dependency-overrides`, `unpinned-git`, `build-number-regression`, `lockfile-out-of-sync` (dependências alteradas sem o `pubspec.lock` correspondente no snapshot) |
| `l10n` | `missing-key`, `placeholder-mismatch`, `unused-key` (lê `l10n.yaml`) |
| `assets` | `missing`, `undeclared`, `max-file-size` |
| `sensitive-files` | `signing` (`key.properties`, keystores, `.p8`/`.p12`), `credentials` (service account JSON, `.env*`) |
| `tests` | `solo`, `new-skip` (só skip introduzido no changeset, nunca os antigos), `affected` (pre-push) |

Severidade padrão: `error`, exceto `l10n/unused-key` e `tests/new-skip`, que são `warning`.

## Roadmap

0. **Spike (primeiro, antes da arquitetura definitiva).**
   - Medir `OverlayResourceProvider` com conteúdo do index num app Flutter grande e real, num commit típico de 3 a 10 arquivos.
   - Medir pelo caminho real de distribuição: o snapshot JIT gerado pelo `pub global activate`, não um binário de `dart compile exe`. Medir a frio e a quente.
   - Teste de paridade: comparar a saída com o `dart format` e o `dart analyze` do SDK do projeto, e decidir o mecanismo da decisão 8.
   - Meta: abaixo de ~2 s. Se não atingir, avaliar um processo persistente (daemon) antes de seguir.
1. **`0.1.0-dev.1`**, para reservar o nome no pub.dev; deliberadamente sem analyzer.
   - `init`, `install`, `uninstall`, `run pre-commit`.
   - `GitClient` com `cat-file --batch`.
   - Checks `pubspec/path-dependency` e `pubspec/dependency-overrides`.
   - Reporter de console.
   - Hook com fallback para Windows, validado por um `git commit` real no runner Windows.
   - Comandos não interativos fora de TTY e instalação de hooks correta em worktree ligado.
   - Testes de aceitação.
2. **`0.1.0`**
   - `format` com autofix seguro.
   - `analyze` afetado com overlay.
   - `sensitive-files`.
   - `run pre-push` sobre o commit enviado.
   - `ci --base` com reporter `github`, e composite action (`action.yml`) que instala e roda o `ci`.
   - Resolução de SDK (`sdk_path`, FVM) e descoberta de pacote pelo `pubspec.yaml` mais próximo.
   - Mapa `rules:`, `exclude` e comentários `stagelatch:ignore`.
   - `doctor`.
   - Reporter `json`.
   - Benchmark reproduzível no README e GIF de terminal gravado com VHS.
3. **`0.2.0`:** `codegen`, `l10n` (sem `unused-key`), `assets`, `pubspec` completo com `lockfile-out-of-sync`, `tests/solo`, `tests/new-skip`, baseline, `--all`, JSON Schema da config.
4. **`0.3.0`:** `tests/affected` (grafo de imports por parse de diretivas), `why`, `l10n/unused-key` (única regra que varre o projeto inteiro; aproveita o grafo e o cache), cache por hash de conteúdo, reporters SARIF e JUnit, pub workspaces.
5. **`1.0.0`:** API pública para checks customizados. Só então avaliar separar um `stagelatch_core`.

## Fora de escopo

- Secret scanning por conteúdo. O `sensitive-files` olha caminho e estrutura do arquivo; para o resto existe gitleaks.
- Lint de mensagem de commit (hook `commit-msg`).
- Execução de plugins do analyzer e de `custom_lint`.
- Telemetria e checagem de atualização (exigiriam rede).
- Daemon, a menos que o spike não atinja a meta.

## Padrões de engenharia

- **Lints:** `very_good_analysis` com `strict-casts`, `strict-inference` e `strict-raw-types`. Zero warnings.
- **Testes:**
  - Unitários no domínio e na aplicação.
  - **Aceitação com repositórios git reais** criados em diretório temporário.
  - Cenários obrigatórios:
    - staging parcial (`git add -p`);
    - rename, delete, arquivo binário;
    - primeiro commit (sem HEAD);
    - merge e rebase em andamento, incluindo o changeset reduzido do merge;
    - pre-push de branch novo e de remoção de branch;
    - `ci` em clone raso;
    - `core.hooksPath` já configurado por outra ferramenta;
    - worktree ligado (`git worktree add`);
    - execução sem TTY (nenhum prompt, saída sem cor);
    - hook disparado por um `git commit` real no Windows;
    - CRLF;
    - paths com espaço e unicode.
- **CI:** matriz Dart stable e beta × ubuntu, macos e windows.
- **Release:**
  - Conventional Commits.
  - `release-please` para versão e CHANGELOG.
  - Publicação no pub.dev via GitHub Actions com OIDC, sem token salvo.
- **Performance:** o pre-commit deve rodar em 1–2 s. Medir e reportar o tempo de cada check.

## Riscos conhecidos a verificar cedo

- **Windows:** `pub global activate` gera `stagelatch.bat`, e o hook roda no `sh` do Git for Windows, que pode não resolver `.bat`. O template da decisão 6 trata isso com dois fallbacks; falta provar no runner Windows, na `0.1.0-dev.1`.
- **Paridade com o SDK:** o `dart_style` e o `analyzer` embutidos podem divergir do SDK do projeto, e aí o gate discorda da IDE. O spike mede e decide (decisão 8).
- **Startup em JIT:** o `pub global activate` roda um snapshot JIT, não AOT. O aquecimento do analyzer pode consumir o orçamento de 1–2 s sozinho.
- **API do analyzer:** muda entre versões maiores. Fixar o range e testar contra o Dart beta no CI.
- **Codegen:** respeitar projetos que **não** versionam arquivos gerados (`generated_files_committed: false`).
