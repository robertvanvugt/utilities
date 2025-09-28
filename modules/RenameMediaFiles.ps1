
# Run this first to rename the files in each folder to prevent overlapping names.
# Then move the files into the same folder.
# Finally, run sortVideoFiles.ps1 to sort the files.

####################################################
#       Rename files to include creator name       #
####################################################

$folderpath = "E:\Pictures\2025\Vakantie USA 2025\LivePhotos"
$Prefix     = "ROB_"

Get-ChildItem -Path $folderpath -File | ForEach-Object {
    $newName = $Prefix + $_.Name
    Rename-Item -Path $_.FullName -NewName $newName
}



####################################################
#       Rename files to .JPEG extension            #
####################################################

Get-ChildItem -Path $folderpath -Filter *.JPG | Rename-Item -NewName { $_.Name -replace '\.JPG$', '.JPEG' }
