## CIAOPS
## Script provided as is. Use at own risk. No guarantees or warranty provided.

## Description
## Script designed to tenant emails to see whether they appear in the haveibeenpwned.com database
## Adapted from the original script by Elliot Munro - https://gcits.com/knowledge-base/check-office-365-accounts-against-have-i-been-pwned-breaches/

## Prerequisites = 1
## 1. Ensure msonline MFA module installed or updated

## Variables
$resultsfile = "c:\downloads\results.csv"   ## local file with credentials if required

Clear-Host

write-host -foregroundcolor green "Script started"

## Script from Elliot start
Connect-MsolService
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$headers = @{
    "User-Agent"  = "$((Get-MsolCompanyInformation).DisplayName) Account Check"
    "api-version" = 2 }

$baseUri = "https://haveibeenpwned.com/api"

# To check for admin status
$RoleId = (Get-MsolRole -RoleName "Company Administrator").ObjectId
$Admins = (Get-MsolRoleMember -RoleObjectId $RoleId | Select-object EmailAddress)
$Report = @()
$Breaches=0

Write-Host "Fetching mailboxes to check..."
$Users = (Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited | Select-object UserPrincipalName, EmailAddresses, DisplayName)
Write-Host "Processing" $Users.count "mailboxes..."

ForEach ($user in $users) {
    $Emails = $User.emailaddresses | Where-Object {$_ -match "smtp:" -and $_ -notmatch ".onmicrosoft.com"}
    $IsAdmin = $False
    $MFAUsed = $False
    $emails | ForEach-Object {
        $Email = ($_ -split ":")[1]
        $uriEncodeEmail = [uri]::EscapeDataString($Email)
        $uri = "$baseUri/breachedaccount/$uriEncodeEmail"
        $BreachResult = $null
        Try {
            [array]$breachResult = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction SilentlyContinue
        }
        Catch {
            if($error[0].Exception.response.StatusCode -match "NotFound"){
                Write-Host "No Breach detected for $email"
            }else{
                Write-Host "Cannot retrieve results due to rate limiting or suspect IP. You may need to try a different computer"
            }
        }
        if ($BreachResult) {
            $MSOUser = Get-MsolUser -UserPrincipalName $User.UserPrincipalName
            If ($Admins -Match $User.UserPrincipalName) {$IsAdmin = $True}
            If ($MSOUser.StrongAuthenticationMethods -ne $Null) {$MFAUsed = $True}
            ForEach ($Breach in $BreachResult) {
                 $ReportLine = [PSCustomObject][ordered]@{
                    Email              = $email
                    UserPrincipalName  = $User.UserPrincipalName
                    Name               = $User.DisplayName
                    LastPasswordChange = $MSOUser.LastPasswordChangeTimestamp
                    BreachName         = $breach.Name
                    BreachTitle        = $breach.Title
                    BreachDate         = $breach.BreachDate
                    BreachAdded        = $breach.AddedDate
                    BreachDescription  = $breach.Description
                    BreachDataClasses  = ($breach.dataclasses -join ", ")
                    IsVerified         = $breach.IsVerified
                    IsFabricated       = $breach.IsFabricated
                    IsActive           = $breach.IsActive
                    IsRetired          = $breach.IsRetired
                    IsSpamList         = $breach.IsSpamList
                    IsTenantAdmin      = $IsAdmin
                    MFAUsed            = $MFAUsed
                }

                $Report += $ReportLine
                Write-Host "Breach detected for $email - $($breach.name)" -ForegroundColor Red
                If ($IsAdmin -eq $True) {Write-Host "This is a tenant administrator account" -ForeGroundColor DarkRed}
                $Breaches++
                Write-Host $breach.Description -ForegroundColor Yellow
            }
        }
        Start-sleep -Milliseconds 2000
    }
}
If ($Breaches -gt 0) {
    $Report | Export-CSV $resultsfile -NoTypeInformation
    Write-Host "Total breaches found: " $Breaches " You can find a report in "$resultsfile }
Else
  { Write-Host "Hurray - no breaches found for your Office 365 mailboxes" }