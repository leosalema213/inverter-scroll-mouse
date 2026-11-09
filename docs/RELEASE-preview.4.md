Prévia nativa para Windows e macOS, sem Electron. Ambos os instaladores têm limite de 10 MB.

- Windows: instalador com entrada UTF-8 explícita, corrigindo a acentuação.
- macOS 13+: app universal para Apple Silicon e Intel, mesmo layout simples, temas claro/escuro, início com o macOS e atualização com SHA-256.
- No Mac, arraste o app para Aplicativos e autorize Acessibilidade quando solicitado. O processo permanece ativo na barra de menus para inverter a roda do mouse. Eventos contínuos (trackpad/rolagem suave) não são invertidos. Alguns mouses com drivers de rolagem suave também emitem eventos contínuos.
- A versão de Mac é uma prévia com assinatura ad hoc, sem notarização Apple. A distribuição pública sem alertas requer Developer ID e notarização. Não desative o Gatekeeper nem remova quarentena automaticamente.
- O CI verifica compilação das duas arquiteturas, assinatura local e testes de eventos sintéticos. O funcionamento físico dos mouses e permissões precisa de validação em um Mac real.
