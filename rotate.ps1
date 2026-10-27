# Rotate + reconnect (PowerShell, called by JS/MCP)
$iface = (netsh wlan show interfaces).Split("`n") | Select-String "State"
# Mock: MAC rotate + reconnect every 50 min (called from node ws.js or server)
Write-Output "MAC rotate triggered $(Get-Date -Format o)"
