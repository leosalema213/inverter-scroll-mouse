Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!include "FileFunc.nsh"

Name "Mouse Scroll"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\Mouse Scroll"
InstallDirRegKey HKCU "Software\MouseScroll" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
VIProductVersion "1.1.0.4"
VIAddVersionKey /LANG=1046 "ProductName" "Mouse Scroll"
VIAddVersionKey /LANG=1046 "ProductVersion" "1.1.0-preview.4"
VIAddVersionKey /LANG=1046 "FileVersion" "1.1.0.4"
VIAddVersionKey /LANG=1046 "FileDescription" "Instalador do Mouse Scroll"
VIAddVersionKey /LANG=1046 "LegalCopyright" "Leo Salema"
!define MUI_ICON "${PROJECT_DIR}\assets\icon.ico"
!define MUI_UNICON "${PROJECT_DIR}\assets\icon.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Bem-vindo ao Mouse Scroll"
!define MUI_WELCOMEPAGE_TEXT "Ajuste a direção da roda dos seus mouses com e sem fio.$\r$\n$\r$\nSuas configurações são preservadas ao atualizar.$\r$\n$\r$\nClique em Próximo para continuar."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
Page custom ConfirmDirectory
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\Mouse Scroll.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Abrir o Mouse Scroll agora"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "PortugueseBR"
Var Updated
Var WaitCount

Function .onInit
  StrCpy $Updated 0
  ${GetParameters} $0
  ${GetOptions} $0 "--updated" $1
  ${IfNot} ${Errors}
    StrCpy $Updated 1
    SetSilent silent
  ${EndIf}
FunctionEnd

Function ConfirmDirectory
  !insertmacro MUI_HEADER_TEXT "Confirmar instalação" "Confira a pasta antes de instalar."
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateLabel} 0 8u 100% 22u "O Mouse Scroll será instalado nesta pasta:"
  Pop $0
  ${NSD_CreateLabel} 0 34u 100% 42u "$INSTDIR"
  Pop $0
  ${NSD_CreateLabel} 0 86u 100% 36u "Clique em Instalar para confirmar ou em Voltar para alterar a pasta."
  Pop $0
  nsDialogs::Show
FunctionEnd

Section "Mouse Scroll" SEC_APP
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  ; The app exits after launching an update. Retry locked files briefly without killing unrelated processes.
  StrCpy $WaitCount 0
  retryCopy:
    ClearErrors
    SetOverwrite on
    File /oname=MouseScroll.new.exe "${APP_EXE}"
    ${If} ${Errors}
      MessageBox MB_ICONSTOP "Não foi possível gravar o aplicativo. Confira a pasta e tente novamente."
      Abort
    ${EndIf}
    Delete "$INSTDIR\Mouse Scroll.exe"
    ${If} ${FileExists} "$INSTDIR\Mouse Scroll.exe"
      Delete "$INSTDIR\MouseScroll.new.exe"
      IntOp $WaitCount $WaitCount + 1
      ${If} $WaitCount < 40
        Sleep 250
        Goto retryCopy
      ${EndIf}
      MessageBox MB_ICONEXCLAMATION "Feche o Mouse Scroll e tente instalar novamente."
      Abort
    ${EndIf}
    Rename "$INSTDIR\MouseScroll.new.exe" "$INSTDIR\Mouse Scroll.exe"
    ${If} ${Errors}
      MessageBox MB_ICONSTOP "Não foi possível instalar. Confira a pasta e tente novamente."
      Abort
    ${EndIf}
  WriteUninstaller "$INSTDIR\Desinstalar.exe"
  File /oname=Lucide-LICENSE.txt "${PROJECT_DIR}\assets\Lucide-LICENSE.txt"
  CreateDirectory "$SMPROGRAMS\Mouse Scroll"
  CreateShortcut "$SMPROGRAMS\Mouse Scroll\Mouse Scroll.lnk" "$INSTDIR\Mouse Scroll.exe"
  CreateShortcut "$DESKTOP\Mouse Scroll.lnk" "$INSTDIR\Mouse Scroll.exe"
  WriteRegStr HKCU "Software\MouseScroll" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll" "DisplayName" "Mouse Scroll"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll" "DisplayVersion" "1.1.0-preview.4"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll" "Publisher" "Leo Salema"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll" "DisplayIcon" "$INSTDIR\Mouse Scroll.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll" "UninstallString" '$\"$INSTDIR\Desinstalar.exe$\"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll" "NoRepair" 1
SectionEnd

Function .onInstSuccess
  ${If} $Updated == 1
    Exec '"$INSTDIR\Mouse Scroll.exe"'
  ${EndIf}
FunctionEnd

Section "Uninstall"
  SetShellVarContext current
  Delete "$INSTDIR\Mouse Scroll.exe"
  Delete "$INSTDIR\Desinstalar.exe"
  Delete "$INSTDIR\Lucide-LICENSE.txt"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\Mouse Scroll.lnk"
  Delete "$SMPROGRAMS\Mouse Scroll\Mouse Scroll.lnk"
  RMDir "$SMPROGRAMS\Mouse Scroll"
  DeleteRegKey HKCU "Software\MouseScroll"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\MouseScroll"
  ; Keep personal preferences and driver direction. Startup can be disabled in the app.
SectionEnd
