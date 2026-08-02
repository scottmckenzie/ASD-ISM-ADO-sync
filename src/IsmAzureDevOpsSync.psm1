Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-Values($o,[string]$name){
  $p=$o.PSObject.Properties['props']; if(-not $p){return @()}
  @($p.Value|Where-Object name -eq $name|ForEach-Object{[string]$_.value})
}
function Get-IsmControls{
  [CmdletBinding()]param([Parameter(Mandatory)]$Catalog,[switch]$IncludePrinciples)
  $out=[Collections.Generic.List[object]]::new()
  function visit($g,[string[]]$path){
    $next=@($path)+@([string]$g.title); $cp=$g.PSObject.Properties['controls']
    foreach($c in @(if($cp){$cp.Value})){
      if(-not $c){continue}; if($c.class-ne'ISM-control'-and-not $IncludePrinciples){continue}
      $pp=$c.PSObject.Properties['parts']; $statement=@(if($pp){$pp.Value|Where-Object name -eq statement|ForEach-Object prose})-join"`n`n"
      $id=([string]$c.id).ToLowerInvariant(); $short=($statement-replace'\s+',' ').Trim()
      if($short.Length-gt 110){$short=$short.Substring(0,107).TrimEnd()+'...'}
      $out.Add([pscustomobject]@{
        Id=$id; Title=if($c.class-eq'ISM-control'){"$($id.ToUpperInvariant()) - $short"}else{[string]$c.title}
        Statement=$statement; Revision=(Get-Values $c revision|Select-Object -First 1)
        Updated=(Get-Values $c updated|Select-Object -First 1); Applicability=(Get-Values $c applicability)-join'; '
        Guideline=if($next.Count-gt 1){$next[1]}else{$next[0]}; Section=$next[-1]; Class=[string]$c.class
      })
    }
    $gp=$g.PSObject.Properties['groups']; foreach($child in @(if($gp){$gp.Value})){if($child){visit $child $next}}
  }
  foreach($g in @($Catalog.groups)){visit $g @()}; $out.ToArray()
}
function Get-Headers([string]$Pat){
  if($Pat){return @{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))}}
  if(-not(Get-Command az -ErrorAction SilentlyContinue)){throw 'Supply -Pat, AZURE_DEVOPS_EXT_PAT, or sign in using Azure CLI.'}
  $t=& az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
  if($LASTEXITCODE-ne 0-or-not $t){throw 'Could not obtain an Azure DevOps token.'}; @{Authorization="Bearer $t"}
}
function Invoke-Ado([string]$Method,[string]$Uri,[hashtable]$Headers,$Body,[string]$ContentType='application/json'){
  $a=@{Method=$Method;Uri=$Uri;Headers=$Headers;ContentType=$ContentType}; if($null-ne$Body){$a.Body=$Body|ConvertTo-Json -Depth 20 -Compress}; Invoke-RestMethod @a
}
function Source-Value($c,[string]$source){switch($source){Id{$c.Id} Title{$c.Title} Statement{$c.Statement} Revision{$c.Revision} Updated{$c.Updated} Applicability{$c.Applicability} Guideline{$c.Guideline} Section{$c.Section} Class{$c.Class} default{throw "Unknown field-map source '$source'."}}}
function Patch([string]$op,[string]$field,$value){@{op=$op;path='/fields/'+($field-replace'~','~0'-replace'/','~1');value=$value}}

function Sync-IsmAzureDevOps{
 [CmdletBinding(SupportsShouldProcess)]param(
  [Parameter(Mandatory)][string]$Organisation,[Parameter(Mandatory)][string]$Project,[string]$WorkItemType='Issue',
  [string]$AreaPath,[string]$IterationPath,[string]$Pat,[string]$OscalUri,[string]$OscalPath,
  [string]$FieldMapPath,[switch]$MarkRetired,[switch]$IncludePrinciples,[switch]$Apply
 )
 if(-not(Test-Path -LiteralPath $FieldMapPath)){throw "Field map not found: $FieldMapPath"}; $map=Get-Content $FieldMapPath -Raw|ConvertFrom-Json
 $doc=if($OscalPath){Get-Content $OscalPath -Raw|ConvertFrom-Json}else{Invoke-RestMethod $OscalUri}; if(-not$doc.catalog){throw 'Input is not an OSCAL catalog.'}
 $controls=@(Get-IsmControls $doc.catalog -IncludePrinciples:$IncludePrinciples); $dup=$controls|Group-Object Id|Where-Object Count -gt 1|Select-Object -First 1; if($dup){throw "Duplicate OSCAL id: $($dup.Name)"}
 $h=Get-Headers $Pat; $org=$Organisation.TrimEnd('/');if($org-notmatch'^https?://'){$org="https://dev.azure.com/$org"};$base="$org/$([Uri]::EscapeDataString($Project))/_apis";$marker='ASD-ISM-Managed'
 $q=Invoke-Ado POST "$base/wit/wiql?api-version=7.1" $h @{query="SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject]=@project AND [System.Tags] CONTAINS '$marker'"};$existing=@{};$ids=@($q.workItems|ForEach-Object id)
 for($i=0;$i-lt$ids.Count;$i+=200){$end=[Math]::Min($i+199,$ids.Count-1);$items=Invoke-Ado GET "$base/wit/workitems?ids=$($ids[$i..$end]-join',')&fields=System.Id,System.Tags&api-version=7.1" $h $null;foreach($w in $items.value){$tag=@(([string]$w.fields.'System.Tags')-split';'|ForEach-Object Trim)|Where-Object{$_-match'^ASD-ISM-ID:'}|Select-Object -First 1;if($tag){$existing[$tag.Substring(11).ToLowerInvariant()]=$w.id}}}
 $created=0;$updated=0;$unchanged=0;$retired=0;$seen=@{}
 foreach($c in $controls){$seen[$c.Id]=$true;$fields=[ordered]@{};foreach($e in $map.fields.PSObject.Properties){$v=Source-Value $c ([string]$e.Value);if($null-ne$v-and[string]$v-ne''){$fields[$e.Name]=$v}};$managed=@($marker,"ASD-ISM-ID:$($c.Id)","ASD-ISM-Version:$($doc.catalog.metadata.version)");if($AreaPath){$fields['System.AreaPath']=$AreaPath};if($IterationPath){$fields['System.IterationPath']=$IterationPath}
  if(-not$existing.ContainsKey($c.Id)){$fields['System.Tags']=$managed-join'; ';$ops=@($fields.GetEnumerator()|ForEach-Object{Patch add $_.Key $_.Value});if($PSCmdlet.ShouldProcess($c.Id,'Create work item')){$type=[Uri]::EscapeDataString($WorkItemType);$null=Invoke-Ado POST "$base/wit/workitems/`$${type}?api-version=7.1" $h $ops 'application/json-patch+json'};$created++;continue}
  $wid=$existing[$c.Id];$current=Invoke-Ado GET "$base/wit/workitems/${wid}?api-version=7.1" $h $null;$tags=@(([string]$current.fields.'System.Tags')-split';'|ForEach-Object Trim|Where-Object{$_});$keep=@($tags|Where-Object{$_-notmatch'^ASD-ISM-(ID|Version):'-and$_-ne$marker-and$_-ne'ASD-ISM-Retired'});$fields['System.Tags']=@($keep+$managed)-join'; ';$ops=@();foreach($f in $fields.Keys){$old=$current.fields.PSObject.Properties[$f];if(-not$old-or[string]$old.Value-ne[string]$fields[$f]){$ops+=Patch $(if($old){'replace'}else{'add'}) $f $fields[$f]}}
  if(-not$ops.Count){$unchanged++;continue};if($PSCmdlet.ShouldProcess("$($c.Id) ($wid)","Update $($ops.Count) managed fields")){$null=Invoke-Ado PATCH "$base/wit/workitems/${wid}?api-version=7.1" $h $ops 'application/json-patch+json'};$updated++
 }
 if($MarkRetired){foreach($id in @($existing.Keys|Where-Object{-not$seen.ContainsKey($_)})){$wid=$existing[$id];$w=Invoke-Ado GET "$base/wit/workitems/${wid}?fields=System.Tags&api-version=7.1" $h $null;$tags=[string]$w.fields.'System.Tags';if($tags-notmatch'(^|;)\s*ASD-ISM-Retired\s*(;|$)'){$ops=@(Patch replace System.Tags "$tags; ASD-ISM-Retired");if($PSCmdlet.ShouldProcess("$id ($wid)",'Mark retired')){$null=Invoke-Ado PATCH "$base/wit/workitems/${wid}?api-version=7.1" $h $ops 'application/json-patch+json'};$retired++}}}
 [pscustomobject]@{CatalogVersion=$doc.catalog.metadata.version;Controls=$controls.Count;Created=$created;Updated=$updated;Unchanged=$unchanged;Retired=$retired;Preview=[bool]$WhatIfPreference}
}
Export-ModuleMember Get-IsmControls,Sync-IsmAzureDevOps
