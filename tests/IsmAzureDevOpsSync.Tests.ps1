BeforeAll { Import-Module "$PSScriptRoot/../src/IsmAzureDevOpsSync.psm1" -Force }
Describe Get-IsmControls {
 It 'extracts nested ISM controls' {
  $control=[pscustomobject]@{id='ISM-0137';class='ISM-control';title='Control';props=@([pscustomobject]@{name='revision';value='4'},[pscustomobject]@{name='applicability';value='NC'});parts=@([pscustomobject]@{name='statement';prose='Do the thing.'})}
  $catalog=[pscustomobject]@{groups=@([pscustomobject]@{title='Guidelines';groups=@([pscustomobject]@{title='Topic';groups=@([pscustomobject]@{title='Section';controls=@($control)})})})}
  $r=@(Get-IsmControls $catalog);$r.Count|Should -Be 1;$r[0].Id|Should -Be 'ism-0137';$r[0].Revision|Should -Be '4';$r[0].Statement|Should -Be 'Do the thing.'
 }
}
