function Get-AdUserGroupMembershipTree {
	param(
		[string]$UserName,
		[switch]$PassThru,
		[switch]$PassThruFlat,
		[string]$ExportToCsv
	)
	
	function log {
		param(
			[string]$msg,
			[int]$L
		)
		for($i = 0; $i -lt $L; $i += 1) {
			$msg = "    $msg"
		}
		Write-Host $msg
	}
	
	function Get-MemberGroups($group, $L) {
		log "$($group.Ancestry)" -L $L
		$flatGroups += @($group.Ancestry)
		
		# Intentionally not using Get-ADGroupMember -Recursive to hopefully improve efficiency by attempting to process non-groups a little as possible, as well as avoid maximum request size limits built into PowerShell module calls to AD services.
		$memberGroups = Get-ADGroupMember -Identity $group.Name | Where { $_.ObjectClass -eq "group" } | Sort "Name" | ForEach-Object {
			$memberGroup = $_
			$memberGroup | Add-Member -NotePropertyName "Ancestry" -NotePropertyValue "$($group.Ancestry)/$($memberGroup.Name)" -Force
			#Get-MemberGroups $memberGroup ($L + 1)
			# This is actually easier to read when it's not indented
			Get-MemberGroups $memberGroup $L
		}
		
		$group | Add-Member -NotePropertyName "MemberGroups" -NotePropertyValue $memberGroups -PassThru
	}
	
	function Do-Stuff {
		log "Building group membership tree for user `"$UserName`"..."
		
		log "Getting direct group memberships..." -L 1
		# Note: Get-ADPrincipalGroupMembership returns only groups where the given user is a direct member. However it also returns the "Domain Users" group, which is not counted as a Direct group by Usersearch.
		$groups = Get-ADPrincipalGroupMembership -Identity $UserName | Where { $_.Name -ne "Domain Users" } | Sort "Name"
		if(-not $groups) {
			log "No direct group memberships found!" -L 2
		}
		else {
			$groupsCount = @($groups).count
			log "Found $groupsCount direct group memberships." -L 2
			
			$flatGroups = @()
			
			$groups | ForEach-Object {
				$group = $_
				$group | Add-Member -NotePropertyName "Ancestry" -NotePropertyValue $group.Name -Force
				$group = Get-MemberGroups $group 3
				$group
			}
			
			$flatGroups = $flatGroups | Sort
			
			if($ExportToCsv) {
				$flatGroups | Export-Csv -Path $ExportToCsv -Encoding "Ascii" -NoTypeInformation
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