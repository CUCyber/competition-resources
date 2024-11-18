# Author: Isaac Fletcher (modified from Tim Koehler's original)
# Script for randomly resetting users' passwords. Users are provided in a CSV file, and results are saved to an output file.

function Generate-Password {
	param (
		[parameter(Mandatory=$false)]
		[ValidateRange(1, 128)]
		[int] $Length	
	)
		
	$p = -join ($acceptable_chars | get-random -Count $Length | foreach {[char]$_}) + "7!";
	return $p
}

$path = $args[0]

Import-Csv $path -Header "Username"

$users_file | ForEach-Object {
        # Read the current username from the CSV
        $user_name = $_.Username
        echo "Resetting password for $user_name..."
        
        # Generate a random password composed of lower and uppercase letters and special characters
        $password = Generate-Password -Length 20
        # Reset password
        net user $user_name $password

        # Save the data to the output file
        Add-Content -Path .\$output_file -Value "$user_name::$password"
}


