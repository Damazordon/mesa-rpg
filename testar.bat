@echo off
rem Importa as classes novas e roda os testes do motor.
rem Funciona de qualquer pasta (usa a pasta deste arquivo) e tanto no cmd quanto no PowerShell.
rem Para usar outro Godot: set GODOT=C:\caminho\godot_console.exe  antes de chamar.
setlocal
if "%GODOT%"=="" set "GODOT=C:\Users\gabri\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Nao achei o Godot em:
  echo   %GODOT%
  echo Rode:  set "GODOT=C:\caminho\do\godot_console.exe"  e chame de novo.
  exit /b 1
)
cd /d "%~dp0"

echo == importando classes novas
"%GODOT%" --headless --path . --import
if errorlevel 1 (
  echo.
  echo O import falhou. Veja os erros de parse acima antes de rodar os testes.
  exit /b 1
)

echo.
echo == testes do motor
"%GODOT%" --headless --path . -- --rules-tests
set CODE=%errorlevel%
echo.
if "%CODE%"=="0" (echo TUDO OK) else (echo HOUVE FALHA ^(codigo %CODE%^))
exit /b %CODE%
