' Abre o painel web do servidor (sem nenhuma janela de console). Se ja estiver aberto, so abre o navegador.
Set fso = CreateObject("Scripting.FileSystemObject")
pasta = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & pasta & "\scripts\Painel.ps1""", 0, False
