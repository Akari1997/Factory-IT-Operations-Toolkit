$dc = "DKAADS-0D1.corp.lego.com"
$base = "LDAP://$dc/DC=corp,DC=lego,DC=com"

$users = Get-Content ".\users.txt"

foreach ($u in $users) {

    $u = $u.Trim()
    if ($u -eq "") { continue }

    try {
        $entry = New-Object System.DirectoryServices.DirectoryEntry($base)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
        $searcher.Filter = "(sAMAccountName=$u)"

        $result = $searcher.FindOne()

        if ($null -eq $result) {
            Write-Output "$u`tNot Found"
            continue
        }

        $expires = $result.Properties["accountExpires"]

        if (
            $expires.Count -eq 0 -or
            $expires[0] -eq 0 -or
            $expires[0] -eq 9223372036854775807
        ) {
            Write-Output "$u`tNever Expired"
        }
        else {
            $date = [DateTime]::FromFileTime([Int64]$expires[0])
            Write-Output "$u`t$date"
        }
    }
    catch {
        Write-Output "$u`tLDAP Query Failed（$($_.Exception.Message))"
    }
}
