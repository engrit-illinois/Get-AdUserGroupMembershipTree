function Get-AdUserGroupMembershipTree {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$true,Position=0)]
		[string]$UserName,
		
		[switch]$ConsoleReport,
		[switch]$PassThru,
		[string]$CsvDir,
		[switch]$TestRun
	)
	
	$COLOR_DIRECT = "green"
	$COLOR_NESTED = $false
	
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
			if($FC -and ($FC -ne $false)) { $params.ForegroundColor = $FC }
			Write-Host @params
		}
	}
	
	function Get-NameFromDn($dn) {
		$dnParts = $dn -split ","
		$dnCn = $dnParts[0]
		$name = $dnCn.Replace("CN=","")
		$name
	}
	
	function Get-UserData {
		try {
			$user = Get-ADUser -Identity $UserName
		}
		catch {
			$userErr = $true
			$userErrRecord = $_
			$userErrMsg = $userErrRecord.Exception.Message
			log "Error getting containers: `"$userErrMsg`"" -L 3 -Verbose
		}
		
		$user
	}
	
	function Get-DirectGroupDns {
		log "Getting direct group memberships..." -L 1
		
		$groups = Get-ADPrincipalGroupMembership -Identity $UserName
		
		if($groups) {
			$groupsCount = @($groups).count
			log "Found $groupsCount direct group memberships." -L 2
		}
		else {
			log "No direct group memberships found!" -L 2
		}
		
		$groups.DistinguishedName | Sort
	}
	
	function Get-GroupsData($groupDns) {
		log "Recursively gathering data for all groups containing groups with direct membership..." -L 1
		
		function Get-GroupData($groupDn, $nesting, $nestingReverse, $L) {
			$groupName = Get-NameFromDn $groupDn
			log $groupName -L $L -Verbose
			
			# Get full group info
			try {
				$group = Get-ADGroup -Identity $groupDN -Properties "Members","MemberOf"
			}
			catch {
				$groupErr = $true
				$groupErrRecord = $_
				$groupErrMsg = $groupErrRecord.Exception.Message
				log "Error getting containers: `"$groupErrMsg`"" -L ($L + 1) -Verbose
			}
			
			if($group) {
				# Build unique string identifying how this group is nested within other groups
				$nesting = "$($groupName)/$($nesting)"
				$nestingReverse = "$($nestingReverse)/$($groupName)"
				log "Nesting: `"$nesting`"" -L ($L + 1) -Verbose
				log "NestingReverse: `"$nestingReverse`"" -L ($L + 1) -Verbose
				
				# Determine whether the user is a direct member of this group, regardless of the nesting path
				$isDirectMemberOfGroup = $false
				if($group.Members -contains $user.DistinguishedName) {
					$isDirectMemberOfGroup = $true
				}
				log "This group itself directly contains `"$UserName`": $isDirectMemberOfGroup" -L ($L + 1) -Verbose
				
				# Determing whether the user is a direct member of this group via this particular nesting path
				$isDirectMemberOfNestingPath = $false
				if($nesting -eq "$($group.Name)/$($UserName)") {
					$isDirectMemberOfNestingPath = $true
				}
				log "This group's nesting path directly contains `"$UserName`": $isDirectMemberOfNestingPath" -L ($L + 1) -Verbose
				
				$containerDns = $group.MemberOf | Sort "Name"
				if($containerDns) {
					$containerDnsCount = @($containerDns).count
					log "Found $containerDnsCount groups containing this group:" -L ($L + 1) -Verbose
					
					$containers = $containerDns | ForEach-Object {
						Get-GroupData $_ $nesting $nestingReverse ($L + 2)
					}
				}
				else {
					if(-not $groupErr) {
						log "Found 0 groups containing this group." -L ($L + 1) -Verbose
					}
				}
			}
			else {
				$group = [PSCustomObject]@{
					DistinguishedName = $groupDn
					Name = $groupName
				}
			}
			
			$group | Add-Member -NotePropertyName "GroupError" -NotePropertyValue $groupHadErr -Force
			$group | Add-Member -NotePropertyName "GroupErrorRecord" -NotePropertyValue $groupErr -Force
			$group | Add-Member -NotePropertyName "GroupErrorMsg" -NotePropertyValue $groupErrMsg -Force
			$group | Add-Member -NotePropertyName "Nesting" -NotePropertyValue $nesting -Force
			$group | Add-Member -NotePropertyName "NestingReverse" -NotePropertyValue $nestingReverse -Force
			$group | Add-Member -NotePropertyName "IsDirectMemberOfGroup" -NotePropertyValue $isDirectMemberOfGroup -Force
			$group | Add-Member -NotePropertyName "IsDirectMemberOfNestingPath" -NotePropertyValue $isDirectMemberOfNestingPath -Force
			$group | Add-Member -NotePropertyName "Containers" -NotePropertyValue $containers -Force
			$containersString = $containers.Name -join ","
			$group | Add-Member -NotePropertyName "ContainersNames" -NotePropertyValue $containersString -Force
			$group | Add-Member -NotePropertyName "MemberOfExpanded" -NotePropertyValue ($group.MemberOf -join ";") -Force
			# Expanding Members was not a good idea, since this will inevitably contain the DistinguishedName of all members of large groups such as Domain Users.
			#$group | Add-Member -NotePropertyName "MembersExpanded" -NotePropertyValue ($group.Members -join ";") -Force
			
			$group
		}
		
		$groupDNs | ForEach-Object {
			Get-GroupData $_ $UserName $UserName 2
		}
	}
	
	function Get-FlatGroups($groups) {
		log "Building flat array of groups..."
		$script:flatGroups = @()
		
		function Get-FlatGroup($group) {
			if($group.Containers) {
				$group.Containers | ForEach-Object {
					Get-FlatGroup $_
				}
			}
			$script:flatGroups += @($group)
		}	
		
		$groups | ForEach-Object {
			Get-FlatGroup $_
		}
		
		$flatGroups | Sort "Nesting"
	}
		
	function Get-NestingColor($group) {
		$color = $COLOR_NESTED
		if($group.IsDirectMemberOfNestingPath) {
			$color = $COLOR_DIRECT
		}
		$color
	}
	
	function Report-FlatGroups($flatGroups) {
		if($ConsoleReport) {
			log "Printing report..."
			$flatGroups | ForEach-Object {
				$group = $_
				$color = Get-NestingColor $group
				log $group.Nesting -L 1 -FC $color
			}
		}
	}
	
	function Do-Stuff {
		log "Building group membership tree for user `"$UserName`"..."
		
		$user = Get-UserData
		
		$groupDns = Get-DirectGroupDns
		
		if($groupDns) {
			$groups = Get-GroupsData $groupDns
			$flatGroups = Get-FlatGroups $groups
			Report-FlatGroups $flatGroups
			
			if($CsvDir) {
				log "Exporting flattened groups to `"$CsvFile`"..."
				$flatGroups | Export-Csv -Path $CsvFile -Encoding "Ascii" -NoTypeInformation
			}
			
			if($PassThru) {
				$flatGroups
			}
		}

	}
	
	Do-Stuff
	
	log "EOF"
}