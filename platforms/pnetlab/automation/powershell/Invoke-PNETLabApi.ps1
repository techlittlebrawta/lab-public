param([Parameter(Mandatory)][string]$BaseUri,[string]$Path='api/status',[ValidateSet('GET','POST','PUT','DELETE')][string]$Method='GET',[string]$Token=$env:PNETLAB_TOKEN)
$headers=@{Accept='application/json'}
if($Token){$headers.Authorization="Bearer $Token"}
Invoke-RestMethod -Uri "$($BaseUri.TrimEnd('/'))/$($Path.TrimStart('/'))" -Method $Method -Headers $headers -ContentType 'application/json'