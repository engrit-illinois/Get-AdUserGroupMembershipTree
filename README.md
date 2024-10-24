# Summary
Returns data representing all the AD groups a given user belongs to, flattened into an array, but retaining information about whether membership in the groups are direct, nested, or both.  

# Requirements
Must be run as your SU account in order for it to see and return all groups. Running as an account without full provileges will return only a subset of group memberships.  

# Usage
1. Download `Get-AdUserGroupMembershipTree.psm1` to the appropriate subdirectory of your PowerShell [modules directory](https://github.com/engrit-illinois/how-to-install-a-custom-powershell-module).
2. Run it using the examples and documentation provided below.

# Parameters

### UserName
Required string.  
The name of the AD user for which to pull group membership data.  

### ConsoleReport
Optional switch.  
If specified, prints an ordered report of all the flattened groups, colorized based on membership type.  

### PassThru
Optional switch.  
If specified returns all of the flattened group data as an array of PowerShell objects.

### CsvDir
Optional string.  
The directory where a CSV will be saved, containing all of the flattened group data, if specified.  

# Notes
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.