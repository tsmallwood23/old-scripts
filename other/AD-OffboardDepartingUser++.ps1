# AD-DisableUserADAccount++.ps1
# By Tech1, with help from many Spiceworks community members and other anonymous Internet denizens

<############################################################################################################

Purpose: Off-loading employees in both Active Directory and Exchange.

Assumes an on-prem Exchange 2010 setup and script run in desktop PowerShell with
Active Directory and Exchange administrator permissions already in place.

Chain:

Active Directory Section:
* Asks admin for a user name to disable.
* Checks for active user with that name.
* Disables user in AD.
* Resets the password of the user's AD account.
* Adds the path of the OU that the user came from to the "Description" of the account.
* Exports a list of the user's group memberships (permissions) to an Excel file in a specified directory.
* Strips group memberships from user's AD account.
* Moves user's AD account to the "Disabled Users" OU.

Exchange email section:
* Asks how to deal with the user's email account.
* Admin chooses one or more of the following:
(1) forward the user's emails to another user
(2) set a reminder to delete the user's account at a certain date and time (30, 60, 90 days)
(3) disable the user's account immediately (30 day retention)
(4) set the mailbox to block incoming emails
(5) leave it open and functional as is.
* Executes said choice, including setting a local reminder in Outlook for admin if needed.
* Sends email to HR confirming everything that has been done to user's account.

############################################################################################################>


$date = [datetime]::Today.ToString('dd-MM-yyyy')

# Un-comment the following if PowerShell isn't already set up to do this on its own
# Import-Module ActiveDirectory

# Blank the console
# Clear-Host
Write-Host "Offboard a user

"

<# --- Active Directory account dispensation section --- #>

# Get the name of the account to disable from the admin
$sam = Read-Host 'Account name to disable'

# Get the properties of the account and set variables
$user = Get-ADuser $sam -properties canonicalName, distinguishedName, displayName, mailNickname
$dn = $user.distinguishedName
$cn = $user.canonicalName
$din = $user.displayName
$UserAlias = $user.mailNickname

# Path building
$path1 = "\\YourFileServer\IT - Share\Documentation\Disabled_Users\"
$path2 = "-AD-DisabledUserPermissions.csv"
$pathFinal = $path1 + $din + $path2

# Disable the account
Disable-ADAccount $sam
Write-Host ($din + "'s Active Directory account is disabled.")

# Reset password
Set-ADAccountPassword -Reset -NewPassword (ConvertTo-SecureString -AsPlainText "seeya!" -Force) $sam
Write-Host ("* " + $din + "'s Active Directory password has been changed.")

# Add the OU path where the account originally came from to the description of the account's properties
Set-ADUser $dn -Description ("Moved from: " + $cn + " - on $date")
Write-Host ("* " + $din + "'s Active Directory account path saved.")

# Get the list of permissions (group names) and export them to a CSV file for safekeeping
$groupinfo = get-aduser $sam -Properties memberof | select name, 
@{ n="GroupMembership"; e={($_.memberof | foreach{get-adgroup $_}).name}}

$count = 0
$arrlist =  New-Object System.Collections.ArrayList
do{
    $null = $arrlist.add([PSCustomObject]@{
        # Name = $groupinfo.name
        GroupMembership = $groupinfo.GroupMembership[$count]
    })
    $count++
}until($count -eq $groupinfo.GroupMembership.count)

$arrlist | select groupmembership |
convertto-csv -NoTypeInformation |
select -Skip 1 |
out-file $pathFinal
Write-Host ("* " + $din + "'s Active Directory group memberships (permissions) exported and saved to " + $pathFinal)

# Strip the permissions from the account
Get-ADUser $User -Properties MemberOf | Select -Expand MemberOf | %{Remove-ADGroupMember $_ -member $User}
Write-Host ("* " + $din + "'s Active Directory group memberships (permissions) stripped from account")

# Move the account to the Disabled Users OU
Move-ADObject -Identity $dn -TargetPath "Ou=Disabled Users,DC=DOMAIN,DC=COMPANY,DC=com"
Write-Host ("* " + $din + "'s Active Directory account moved to 'Disabled Users' OU")

<# --- Exchange email account dispensation section --- #>

# Import the Exchange snapin (assumes desktop PowerShell)
if (!(Get-PSSnapin | where {$_.Name -eq "Microsoft.Exchange.Management.PowerShell.E2010"})) { 

	$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionURI http://YourExchangeServer.DOMAIN.COMPANY.com/powershell/ -Authentication kerberos
	import-PSSession $session 

}

# Loop flag variables
$Go1 = 0
$Go2 = 0
$Go3 = 0
$GoDone = 0

Function Save-File ([string]$initialDirectory) {

	$PresAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
	$AdminCheck = Get-ManagementRoleAssignment -RoleAssignee "$PresAdmin" -Role "Mailbox Import Export" -RoleAssigneeType user
	If ($AdminCheck -eq $Null) {New-ManagementRoleAssignment -Role "Mailbox Import Export" -User $PresAdmin}

	$MailBackupFileDate = (get-date -UFormat %b-%d-%Y_%I.%M.%S%p)
	$MailBackupInitialPath = "\\yourFileServer\Install\IT - Share\Documentation\Disabled_Users\Mailbox_Backups\"
	$MailBackupFileName = "$UserAlias-MailboxBackup-$MailBackupFileDate.pst"

    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $OpenFileDialog.initialDirectory = $MailBackupInitialPath
    $OpenFileDialog.filter = "PST (*.pst)| *.pst"
	$OpenFileDialog.FileName = $MailBackupFileName
    $OpenFileDialog.ShowDialog() | Out-Null

    return $OpenFileDialog.filename

}

While ($GoDone -ne 1) {

	While ($Go1 -ne 1) {

		# Ask admin what they want to do with user's email
		$EmailWhat = Read-Host "What would you like to do with the user's email account? (1, 2, 3, or 4)
		
		Choices: 
		1) Forward the user's email to another user and send a reminder to delete email account by hand.
		2) Leave in place but send a reminder to delete email account by hand.
		3) Disable email account (auto-deleted after 30 days).
		4) Block incoming emails to mailbox and leave in place.
		5) Leave it alone or exit.
		
		
		"

		If ($EmailWhat -eq "1") {

			# Forward email to manager or other user
			Clear-Host
			
			Write-Host "Forward the user's email to a manager or other user and set a reminder selected.
			
			"
			Write-Host "To do so, Outlook must first be closed."
			Read-Host "Press any key ..."
			Write-Host ""
			Get-Process Outlook | Foreach-Object { $_.CloseMainWindow() | Out-Null } | stop-process –force
			
			$ForEm = Read-Host "Email account to forward mails to? {example: jed@COMPANY.com)"
			Set-Mailbox $UserAlias -ForwardingsmtpAddress $ForEm -DeliverToMailboxAndForward $False
			
			#Set reminder for disabling email account?
			While ($Go2 -ne "1") {
				
				Write-Host "Setting reminder.
				
				"
				While ($Go3 -ne "1") {
				
					$DelDate = Read-Host "How many days before deletion reminder? (example: 30, 60, 90)
					
					"
				
					If ($DelDate -ne "30" -AND $DelDate -ne "60" -AND  $DelDate -ne "90") {
						
						Clear-Host
						Write-Host "I'm sorry, I didn't understand. You typed '$DelDate'. Please input '30', '60', or '90'.
						
						"
					
					} Else {
					
						$Go3 = 1
					
					}
					
				}
				
				
				$ol = New-Object -ComObject Outlook.Application
				$meeting = $ol.CreateItem('olAppointmentItem')
				$meeting.Subject = 'Remove email account reminder'
				$meeting.Body = "Please disable " + $User.Name + "'s email account."
				$meeting.Location = 'Exchange Management Console'
				$meeting.ReminderSet = $true
				$meeting.Importance = 1
				$meeting.MeetingStatus = [Microsoft.Office.Interop.Outlook.OlMeetingStatus]::olMeeting
				$meeting.Recipients.Add('Tech2@COMPANY.com')
				$meeting.Recipients.Add('Tech2@COMPANY.com')
				$meeting.ReminderMinutesBeforeStart = 0
				$meeting.Start = (get-date "7:00").adddays($deldate)
				$meeting.Duration = 1
				$meeting.Send()
				$Go2 = 1
			
				
			}
			
			$EmMessage = ("The user's email, " + $sam + "@COMPANY.com, has been forwarded to $ForEm.")
			
			$GoDone = 1
			

		} ElseIf ($EmailWhat -eq "2") {

			#Set reminder for disabling email account?
			While ($Go2 -ne "1") {
				
				Clear-Host
				
				Write-Host "leave in place but set reminder selection chosen.
				
				"
				Write-Host "To do so, Outlook must first be closed."
				Read-Host "Press any key ..."
				Write-Host ""
				Get-Process Outlook | Foreach-Object { $_.CloseMainWindow() | Out-Null } | stop-process –force
			
				While ($Go3 -ne "1") {
				
					$DelDate = Read-Host "How many days before deletion reminder? (example: 30, 60, 90)
					
					"
				
					If ($DelDate -ne "30" -AND $DelDate -ne "60" -AND  $DelDate -ne "90") {
						
						Clear-Host
						Write-Host "I'm sorry, I didn't understand. You typed '$DelDate'. Please input '30', '60', or '90'.
						
						"
					
					} Else {
					
						$Go3 = 1
					
					}
					
				}
				
				$ol = New-Object -ComObject Outlook.Application
				$meeting = $ol.CreateItem('olAppointmentItem')
				$meeting.Subject = 'Remove email account reminder'
				$meeting.Body = "Please disable " + $User.Name + "'s email account."
				$meeting.Location = 'Exchange Management Console'
				$meeting.ReminderSet = $true
				$meeting.Importance = 1
				$meeting.MeetingStatus = [Microsoft.Office.Interop.Outlook.OlMeetingStatus]::olMeeting
				$meeting.Recipients.Add('Tech1@COMPANY.com')
				$meeting.Recipients.Add('Tech2@COMPANY.com')
				$meeting.ReminderMinutesBeforeStart = 15
				$meeting.Start = (get-date "7:00").adddays($deldate)
				$meeting.Duration = 1
				$meeting.Send()
				$Go2 = 1
				
				
			}
			
			$EmMessage = "Unless otherwise ordered, the user's email account, $sam@COMPANY.com, will be deleted from the email Exchange by the Admin in $DelDate days."
			
			$Go1 = 1

		} ElseIf ($EmailWhat -eq "3") {
			
			# Disable the email account
			Clear-Host
			
			Write-Host "Disable email account (auto-deleted after 30 days) selection chosen.
			
			"
			Disable-Mailbox -Identity $user.sAMAccountName -Confirm:$true
			
			$EmMessage = "The user's email account, $sam@COMPANY.com, has been disabled & moved to the 'Disconnected Users' folder on the email Exchange. This means it will be automatically deleted by the Exchange in 30 days."
			
			$Go1 = 1

		} ElseIf ($EmailWhat -eq "4") {
			
			# Block incoming emails to mailbox and leave in place.
			Clear-Host
			Write-Host "Block incoming emails to mailbox selection chosen.
			
			"
			
			Set-Mailbox -Identity $user -AcceptMessageOnlyFrom
			Administrator -RequireSenderAuthenticationEnabled $True
			-MaxReceiveSize 1KB
			
			$EmMessage = "The user's email account, $sam@COMPANY.com, has been disabled and left in place on the email Exchange for future use."
			
			$Go1 = 1	
			
		} ElseIf ($EmailWhat -eq "5") {
			
			# Leave Alone
			Clear-Host
			Write-Host "Leave Alone selection chosen. Exiting.
			
			"
			
			$EmMessage = "The user's email account, $sam@COMPANY.com, has NOT been disabled and has been left in place on the email Exchange for future use. There are no plans to delete it at this time. Understand that this means the email address is open and receiving email and will be doing so indefinitely. This could pose a security risk."
			
			$GoDone = 1
		
		} Else {

			Clear-Host
			Write-Host "I'm sorry, I didn't understand. You typed '$EmailWhat'. Please only input '1', '2', '3', '4', or '5'.
			
			"

		}
		
	}
	
}

$MailBackupFile = Save-File
New-MailboxExportRequest -Mailbox $sam -FilePath $MailBackupFile
Write-Host ""
Write-Host "Mailbox for $UserName was exported as a .PST file."
Write-Host ""

Write-Host "Outlook will now restart"

#Recursively search for Outlook and launch it.
$OutlookPath = Get-ChildItem -Path "C:\Program Files\Microsoft Office\" -Include "Outlook.exe" -Recurse -ErrorAction silentlycontinue| % { $_.fullname } 
&$OutlookPath

#Send email to HR
$MailTo = "Your HR Manager <HR@COMPANY.com>", "IT Helpdesk <IT@COMPANY.com>"
$PicPath = "\\YourFileServer\COMPANY\Public\COMPANY Docs\Logos\COMPANY_CMYK.jpg"

$MailParams = @{

	SmtpServer 	= "YourExchangeServer.DOMAIN.COMPANY.com"
	Attachment 	= $PicPath
	From       	= "HelpDesk@COMPANY.com"
	To         	= $MailTo
	BCC        	= "Tech1@COMPANY.com"
	Subject    	= "COMPANY network user accounts for $din out-processed"
	Body       	= "Hello,<br><br>
	
This is an automated message to let you know that the terminated user, $dn, has been out-processed from the network by the IT Department.<br><br>

The following actions were taken:<br>
Display Name = $din<br><br>
<u>Network</u><br>
* The user's Active Directory account was disabled and moved from $cn on $date to the disabled folder.<br>
* The user's Active Directory account's password was changed.<br>
* The user's Active Directory security permissions were stripped and exported to an Excel file in:<br>
  '$pathFinal'<br><br>

<u>Email</U><br>
* $EmMessage<br>
* Mailbox was exported as a .PST file to:<br>
  '$MailBackupFile'<br><br>

~ Your IT Department<br><br>
<img src='cid:COMPANY_CMYK.jpg'><br>
<H5>Tech1 - Ph: 7007 - Em: Tech1@COMPANY.com<br>
Tech2 - Ph: 7008 - Em: Tech2@COMPANY.com<//H5><br><br>

<H6>Automated user off-boarding script written for COMPANY Inc. by Tech1 &copy;2018 using Microsoft PowerShell.</H6><br>"

	BodyAsHtml = $true
	
}
		
Send-MailMessage @MailParams

Write-Host "Mischief Managed."

