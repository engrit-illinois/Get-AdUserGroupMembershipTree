function Get-AdUserGroupMembershipTree {
	[CmdletBinding()]
	param(
		[string]$UserName,
		[switch]$PassThru,
		[switch]$PassThruFlat,
		[string]$CsvDir
	)
	
	$COLOR_DIRECT = "green"
	$COLOR_DIRECT_NESTEDUNKNOWN = "purple"
	$COLOR_NESTED = "red"
	$COLOR_NESTED_DIRECTUNKNOWN = "pink"
	$COLOR_BOTH = "yellow"
	$COLOR_UNKNOWN = "cyan"
	
	$ErrorActionPreference = "Stop"
	
	$ts = Get-Date -Format "FileDateTime"
	$CsvFile = "$($CsvDir)\Get-AdUserGroupMembershipTree_$($UserName)_$($ts).csv"
	
	function log {
		param(
			[string]$msg,
			[int]$L,
			[string]$FC,
			[switch]$Verbose
		)
		for($i = 0; $i -lt $L; $i += 1) {
			$msg = "    $msg"
		}
		
		$params = @{
			Object = $msg
		}
		
		if($Verbose) {
			Write-Verbose -Message $msg
		}
		else {
			if($FC) { $params.ForegroundColor = $FC }
			Write-Host @params
		}
	}
	
	function Get-GroupData($group, $L) {
		$isDirectMember = $false
		$group2 = $null
		$members = $null
		$groupHadErr = $false
		$groupErr = $null
		$groupErrMsg = $null
		$membersHadErr = $false
		$membersErr = $null
		$membersErrMsg = $null
		$memberGroups = $null
		
		# Here our $group variable contains the results of either Get-ADPrincipleGroupMembership (in the case of the original direct membership groups),
		# or the results of Get-ADGroupMember (in the case of all descendent member groups).
		# The latter is lacking some properties (specifically GroupCategory and GroupScope), so replace this data with consistent output from Get-ADGroup.
		# Note: this can fail if a group's SAM Account Name does not match its CanonicalName/DistinguishedName.
		$ancestry = $group.Ancestry
		log $ancestry -L $L
		try {
			$group2 = Get-ADGroup -Identity $group.Name
		}
		catch {
			$groupHadErr = $true
			$groupErr = $_
			$groupErrMsg = $groupErr.Exception.Message
			log "Error getting group data: `"$groupErrMsg`"" -L ($L + 1) -Verbose
		}
		
		if($group2) {
			$group = $null
			$group = $group2
			$group | Add-Member -NotePropertyName "Ancestry" -NotePropertyValue $ancestry -Force
		
			try {
				# Intentionally not using Get-ADGroupMember -Recursive to hopefully improve efficiency by attempting to process non-groups a little as possible, as well as avoid maximum request size limits built into PowerShell module calls to AD services.
				$members = Get-ADGroupMember -Identity $group.Name
			}
			catch {
				$membersHadErr = $true
				$membersErr = $_
				$membersErrMsg = $membersErr.Exception.Message
				log "Error getting members: `"$membersErrMsg`"" -L ($L + 1) -Verbose
			}
			
			
			if($members) {
				$membersCount = @($members).count
				
				
				$memberGroups = $members | Where { $_.ObjectClass -eq "group" }
				$memberGroupsCount = 0
				if($memberGroups) {
					$memberGroupsCount = @($memberGroups).count
				}
				$memberUsersCount = $membersCount - $memberGroupsCount
				log "Found $membersCount members: $memberGroupsCount groups, $memberUsersCount users." -L ($L + 1) -Verbose
				
				if($members.Name -contains $UserName) {
					$isDirectMember = $true
				}
				log "Contains `"$UserName`": $isDirectMember" -L ($L + 1) -Verbose
				
				if($memberGroups) {
					$memberGroups | Sort "Name" | ForEach-Object {
						$memberGroup = $_
						$memberGroup | Add-Member -NotePropertyName "Ancestry" -NotePropertyValue "$($ancestry)/$($memberGroup.Name)" -Force
						#Get-MemberGroups $memberGroup ($L + 1)
						# This is actually easier to read when it's not indented
						Get-GroupData $memberGroup $L
					}
				}
			}
			else {
				if(-not $membersErr) {
					log "Found 0 members." -L ($L + 1) -Verbose
				}
			}
		}
		else {
			log "Failed to find group!" -L ($L + 1) -Verbose
		}
		
		$group | Add-Member -NotePropertyName "GroupError" -NotePropertyValue $groupHadErr -Force
		$group | Add-Member -NotePropertyName "GroupErrorRecord" -NotePropertyValue $groupErr -Force
		$group | Add-Member -NotePropertyName "GroupErrorMsg" -NotePropertyValue $groupErrMsg -Force		
		$group | Add-Member -NotePropertyName "MembersError" -NotePropertyValue $membersHadErr -Force
		$group | Add-Member -NotePropertyName "MembersErrorRecord" -NotePropertyValue $membersErr -Force
		$group | Add-Member -NotePropertyName "MembersErrorMsg" -NotePropertyValue $membersErrMsg -Force
		$group | Add-Member -NotePropertyName "IsDirectMember" -NotePropertyValue $isDirectMember -Force
		$group | Add-Member -NotePropertyName "MemberGroups" -NotePropertyValue $memberGroups -Force
		$memberGroupsStringArray = $memberGroups.Name -join ","
		$group | Add-Member -NotePropertyName "MemberGroupsStringArray" -NotePropertyValue $memberGroupsStringArray -Force
		
		$script:flatGroups += @($group)
		
		$group
	}
	
	function Do-Stuff {
		log "Building group membership tree for user `"$UserName`"..."
		
		log "Getting direct group memberships..." -L 1
		# Note: Get-ADPrincipalGroupMembership returns only groups where the given user is a direct member. However it also returns the "Domain Users" group, which is not counted as a Direct group by Usersearch.
		$groups = Get-ADPrincipalGroupMembership -Identity $UserName | Sort "Name"
		if(-not $groups) {
			log "No direct group memberships found!" -L 2
		}
		else {
			$groupsCount = @($groups).count
			log "Found $groupsCount direct group memberships." -L 2
			log "Recursively checking all member groups of these $groupsCount groups..." -L 2
			
			$script:flatGroups = @()
			
			$groups = $groups | ForEach-Object {
				$group = $_
				$group | Add-Member -NotePropertyName "Ancestry" -NotePropertyValue $group.Name -Force
				$group = Get-GroupData $group 3
				$group
			}
			
			$flatGroups = $flatGroups | Sort "Ancestry"
			
			if($CsvDir) {
				log "Exporting flat group data to `"$CsvFile`"..."
				$flatGroups | Export-Csv -Path $CsvFile -Encoding "Ascii" -NoTypeInformation
			}
			
			if($PassThru) {
				if($PassThruFlat) {
					$flatGroups
				}
				else {
					$groups
				}
			}
		}

	}
	
	Do-Stuff
	
	log "EOF"
}