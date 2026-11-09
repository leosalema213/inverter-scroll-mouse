# Histórico

## 1.1.0-preview.4

- Corrigida a acentuação do instalador NSIS com BOM UTF-8 e entrada UTF-8 explícita.
- Versão nativa macOS 13+ em Swift/AppKit, universal Intel/Apple Silicon, com o layout simples, temas e ícones compartilhados.
- macOS: inversão de eventos discretos da roda, preservação de eventos contínuos, permissão de Acessibilidade, item de início e processo leve na barra de menus.
- Build automatizado Windows/macOS, limite de 10 MB e publicação de ambos os pacotes na mesma prévia do repositório.

## 1.1.0-preview.3

- Corrigido o salvamento ao alternar temas: substituição atômica sem caminho de backup vazio.
- Ícones Sun, Moon e Settings com os mesmos desenhos Lucide usados no Organon.
- Seletor e botões com altura de 34 px e alinhamento comum, incluindo acabamento escuro do seletor.
- Conferência visual agora grava e relê as preferências em cada troca de tema.

## 1.1.0-preview.2

- Removido o Electron. Executável e instalador nativos abaixo de 1 MB, sem runtime adicional.
- Restaurado o layout original de 820 × 540: lista de mouses, direção e início com o Windows nas mesmas posições.
- Mantidos apenas o novo logo e as paletas do Organon, com tema e engrenagem no header.
- Configurações simples para atualização, com aviso ao abrir, download verificado e reinício pelo instalador NSIS.
- Preservados o perfil da prévia anterior, as cópias locais e o mecanismo original de ajuste e início automático.

## 1.1.0-preview.1

- Interface Electron com a identidade da família Organon: temas claro, escuro e do sistema, controles compactos e nova marca vetorial.
- Instalador NSIS em português com escolha de pasta, confirmação e preservação das preferências.
- Atualizador com aviso ao abrir, consulta manual nas configurações, progresso, verificação SHA-256 e instalação silenciosa com reabertura.
- Canal de versões: `leosalema213/inverter-scroll-mouse`. Previews não são oferecidos pelo canal estável.
- Cópias locais das preferências, direção por dispositivo e estado da tarefa antes de alterar o Windows; mantém as 20 mais recentes.
- Mantido o mecanismo PowerShell de ajuste e a tarefa de início automático sem Electron em segundo plano.

## 1.0.0

- Executável nativo com interface Windows Forms, ajuste de direção e início automático.
