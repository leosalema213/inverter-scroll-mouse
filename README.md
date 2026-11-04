# Mouse Scroll

Utilitário para Windows 10 e 11 que encontra os dispositivos da classe Mouse e altera a direção da roda vertical nos drivers compatíveis com `FlipFlopWheel`. Funciona com os registros USB e sem fio do Attack Shark, incluindo registros antigos ainda presentes no Windows.

1. Abra **Mouse Scroll.exe** ou, se estiver usando os arquivos fonte, **Abrir Mouse Scroll.cmd**.
2. Escolha **Invertida** ou **Padrão** e clique em **Aplicar a todos**. Aceite a solicitação de administrador. Mouses conectados cuja configuração mudou podem reiniciar por alguns segundos.
3. Em **Início com o Windows**, clique em **Ativar** para reaplicar a direção escolhida sempre que você entrar no Windows. A tarefa do Agendador roda sem abrir a janela. Para mudar a direção salva, selecione a nova direção e clique novamente em **Ativar**. Para remover a tarefa, use **Desativar**.

A configuração de início automático requer uma conta administradora. Ela instala uma cópia do script em Program Files e registra uma tarefa para a conta atual. O início automático verifica os dispositivos ao entrar no Windows. Se o Windows criar um registro depois do login, use **Aplicar a todos**.

A lista inclui registros históricos e drivers sem suporte ao ajuste. Se a direção não mudar após aplicar, reconecte o mouse ou reinicie o Windows. O resultado da última execução pode ser consultado em `%LOCALAPPDATA%\MouseScroll.log`.

## Executável

Para compilar, abra o Windows PowerShell 5.1 na pasta do projeto e rode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
```

O executável fica em `dist\Mouse Scroll.exe` e inclui o script e os ícones. Mova o arquivo para o local onde pretende guardá-lo antes de criar atalhos. Para fixar na barra de tarefas, abra o EXE, clique com o botão direito no ícone do Mouse Scroll e escolha **Fixar na barra de tarefas**.
