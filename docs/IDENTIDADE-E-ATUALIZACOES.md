# Consistência com o Organon

Referência consultada: projeto vizinho `estudo-desktop` (Organon 0.7.1), incluindo `src/theme.css`, `src/density.css`, `src/branding.css`, `src/typography.css`, `src/Updates.jsx`, `electron/updates.cjs`, `electron/main.cjs`, `build/installer.nsh` e os símbolos de `assets/branding/`. Também foi consultado o histórico do chat “Organon — quadro amplo e minutos no…”.

## Identidade aplicada

- Layout Windows Forms original de 820 × 540, Segoe UI 10 pt, header de 108 px, lista de dispositivos e painel inferior preservados. Sem sidebar, cards adicionais ou textos de apresentação.
- Tema claro: fundo `#f6f7f9`, cartões brancos, texto `#282938`, acento `#7460d8`.
- Tema escuro: fundo `#101010`, lateral `#141414`, cartões `#191919`, texto `#ededed`, botões `#e5e5e5`. Cinzas neutros, sem tonalidade azul.
- Marca em creme `#f5edd9`, símbolo de mouse com terminais serifados inspirados na marca do Organon, tile com degradê `#303030` → `#101010`. Fontes da marca permanecem locais e o símbolo é SVG editável.
- Margens originais de 24 px e controles nas posições anteriores. Troca de tema e engrenagem no canto superior direito do header.

## Instalação e tamanho

O executável usa Windows Forms/.NET Framework e PowerShell do próprio Windows. O instalador usa NSIS diretamente: português, boas-vindas, pasta personalizável, confirmação, conclusão e atualização silenciosa. Não há Electron, Node.js ou Chromium. A prévia anterior de 121 MB foi substituída por um executável de aproximadamente 200 KB e instalador de aproximadamente 167 KB. O build rejeita executável ou instalador acima de 10.000.000 bytes.

O início automático continua usando a tarefa `MouseScroll-<SID>` e uma cópia do PowerShell em Program Files. Não abre nem mantém o Electron em execução. A tarefa existente e os valores `FlipFlopWheel` são lidos na primeira abertura; não há redefinição nem migração destrutiva.

## Preferências e cópias locais

Perfil em `%APPDATA%/mouse-scroll`, preservando os dados da prévia anterior (ou perfil isolado com `--profile <pasta>`). `preferences.json` guarda versão de contrato 1, tema `system|light|dark` e direção `0|1`; escrita por arquivo temporário + substituição atômica. Arquivos inválidos são preservados e geram erro. Na primeira abertura segue o sistema; o botão no header alterna claro/escuro.

Antes de cada ação administrativa é salvo `backups/<data>.json` com preferências, SID, registros dos mouses e estado da tarefa. Mantêm-se 20 snapshots do aplicativo. São registros para recuperação manual/diagnóstico; não há botão de restauração automática de Registro, nem equivalência com os backups completos de estudos/livros do Organon. Falha ao salvar a cópia impede a alteração. Logs continuam em `%LOCALAPPDATA%/MouseScroll.log`.

A desinstalação preserva preferências, snapshots e direção dos drivers. A tarefa de reaplicação é independente do Electron; desative o início automático pelo app se também quiser removê-la.

## Atualização

Canal próprio: `https://api.github.com/repos/leosalema213/inverter-scroll-mouse/releases/latest`. Nunca consulta nem instala versões do Organon. Consulta ao abrir após dois segundos e manualmente em Configurações. Sem rede, apresenta falha recuperável e continua utilizável.

Somente Releases estáveis com versão semântica superior são oferecidas. A versão final supera o preview de mesma base. O instalador deve se chamar `MouseScroll-Instalar.exe`, com digest SHA-256 do GitHub ou arquivo `MouseScroll-Instalar.exe.sha256`. Download vai para arquivo parcial, confere tamanho e hash e só então permite instalação. Revalida o hash antes de executar `/S --updated --force-run`, fecha o app e o instalador o reabre. Preferências, snapshots e tarefas permanecem.

O aviso só oferece atualização disponível; o usuário pode adiar, baixar em segundo plano e escolher quando reiniciar. Previews devem ser publicados como prerelease, fora do canal estável. Configuração de um canal não publica uma Release: o fluxo com servidor e instalação precisa de uma versão publicada para validação real.

## Publicação

Depois da validação do preview, definir a versão estável em `MouseScroll.Native.cs`, `MouseScrollLauncher.cs`, `Build.ps1`, `build/native-installer.nsi` e `CHANGELOG.md`; gerar com `Build.ps1 -Installer` e publicar instalador e SHA-256 em uma Release estável `v<versão>`. O script PowerShell, o código de suporte e os ícones são embutidos no executável; o SHA-256 é gerado junto do instalador. O atualizador também recusa instaladores acima de 10 MB.

## Verificação

`Test.ps1` cobre comparação de versões, integridade do download/instalador, origem permitida, limite de tamanho, arquivos alterados, falhas de rede e exclusão de prereleases do canal estável. `Mouse Scroll.exe --capture <pasta>` renderiza os temas e configurações em perfil isolado e fecha, sem mudar os mouses. A leitura de dispositivos usa o mesmo código original.

Aplicação de direção e ativação/desativação de tarefas passam pela permissão de administrador e devem ser validadas pelo usuário no preview. O teste de UI não executa essas mudanças nem um instalador baixado.
