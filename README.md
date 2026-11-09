# Mouse Scroll

Disponível para **Windows 10/11** e **macOS 13 ou posterior**. Os dois aplicativos são nativos e seus instaladores têm limite de 10 MB. Os pacotes são publicados juntos nas [Releases](https://github.com/leosalema213/inverter-scroll-mouse/releases).

Utilitário para Windows 10 e 11 que encontra os dispositivos da classe Mouse e altera a direção da roda vertical nos drivers compatíveis com `FlipFlopWheel`. Funciona com os registros USB e sem fio do Attack Shark, incluindo registros antigos ainda presentes no Windows.

A interface mantém o layout nativo original e compartilha as paletas e o logo da família Organon. O botão de tema no topo alterna entre claro e escuro; a engrenagem abre **Configurações** para verificar atualizações, que também são avisadas ao abrir. Usa o .NET Framework do Windows, sem Electron, Node.js ou runtime adicional. Executável e instalador devem ficar abaixo de 10 MB. O canal de atualização é `leosalema213/inverter-scroll-mouse`.

1. Abra **Mouse Scroll.exe** ou, se estiver usando os arquivos fonte, **Abrir Mouse Scroll.cmd**.
2. Escolha **Invertida** ou **Padrão** e clique em **Aplicar a todos**. Aceite a solicitação de administrador. Mouses conectados cuja configuração mudou podem reiniciar por alguns segundos.
3. Em **Início com o Windows**, clique em **Ativar** para reaplicar a direção escolhida sempre que você entrar no Windows. A tarefa do Agendador roda sem abrir a janela. Para mudar a direção salva, selecione a nova direção e clique novamente em **Ativar**. Para remover a tarefa, use **Desativar**.

A configuração de início automático requer uma conta administradora. Ela instala uma cópia do script em Program Files e registra uma tarefa para a conta atual. O início automático verifica os dispositivos ao entrar no Windows. Se o Windows criar um registro depois do login, use **Aplicar a todos**.

A lista inclui registros históricos e drivers sem suporte ao ajuste. Se a direção não mudar após aplicar, reconecte o mouse ou reinicie o Windows. O resultado da última execução pode ser consultado em `%LOCALAPPDATA%\MouseScroll.log`.

## Instalador

Com NSIS 3 instalado, gere o instalador pelo Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -Installer
```

Saída: `release/<versão>/MouseScroll-Instalar.exe` e seu `.sha256`. Use `-NsisPath 'C:\caminho\makensis.exe'` se o compilador estiver fora da pasta padrão. O instalador preserva as preferências ao atualizar. Antes de ações administrativas são guardadas até 20 cópias das configurações em `%APPDATA%\mouse-scroll\backups`; não é necessário configurar backup manual.

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test.ps1` verifica o atualizador nativo sem alterar os mouses. Detalhes de identidade, dados e publicação: [docs/IDENTIDADE-E-ATUALIZACOES.md](docs/IDENTIDADE-E-ATUALIZACOES.md).

## Executável portátil

Para compilar, abra o Windows PowerShell 5.1 na pasta do projeto e rode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
```

O executável fica em `dist\Mouse Scroll.exe` e inclui o script e os ícones. Mova o arquivo para o local onde pretende guardá-lo antes de criar atalhos. Para fixar na barra de tarefas, abra o EXE, clique com o botão direito no ícone do Mouse Scroll e escolha **Fixar na barra de tarefas**.

## macOS

Baixe `MouseScroll-macOS.dmg`, abra e arraste **Mouse Scroll** para **Aplicativos**. O pacote universal funciona em Apple Silicon e Intel. Abra o app, escolha a direção e clique em **Aplicar a todos**. Autorize **Acessibilidade** quando o macOS solicitar e clique em aplicar novamente. O app permanece na barra de menus porque a inversão no Mac precisa de um processo ativo; fechar a janela não encerra o ajuste. Use **Sair** na barra de menus para encerrar.

A inversão é relativa à direção configurada no sistema e afeta eventos discretos da roda. Eventos contínuos (trackpads e alguns drivers de rolagem suave) são preservados. O ajuste do Windows continua sendo feito no Registro; o Mac usa um filtro de eventos local e não altera configurações do trackpad.

A prévia macOS tem assinatura ad hoc e não é notarizada pela Apple. A assinatura Developer ID e a notarização são necessárias para distribuição sem alertas do Gatekeeper. O build não desativa proteções do macOS.

Para compilar em um Mac com Xcode Command Line Tools: `bash macos/build.sh`. O GitHub Actions gera o `.dmg` e o instalador Windows e roda os testes nativos; ambos são anexados à mesma prerelease. A validação física de dispositivos e permissões deve ser feita em um Mac real. Detalhes em [docs/RELEASE-preview.4.md](docs/RELEASE-preview.4.md).
