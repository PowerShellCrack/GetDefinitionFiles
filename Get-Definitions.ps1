<#
    .SYNOPSIS
        Download antimalware definition update files for Microsoft and McAfee

    .DESCRIPTION
        Based on: How to manually download the latest antimalware definition updates for
        Microsoft Forefront Client Security, Microsoft Forefront Endpoint
        Protection 2010 and Microsoft System Center 2012 Endpoint Protection

    .EXAMPLE
        powershell.exe -ExecutionPolicy Bypass -file "Get-Definitions.ps1"

    .NOTES
        Script name: Get-Definitions.ps1
        Author:      Richard Tracy
        Version:     2.0.0
        DateCreated: 07/22/2015
        LastUpdate:  05/15/2018

    .LINK
        https://www.mcafee.com/apps/downloads/security-updates/security-updates.aspx
        http://support.microsoft.com/kb/935934/en


    .LOG
        2.0.0 - May 15, 2019 - Added Get-ScriptPath function to support VScode and ISE
        1.0.0 - July 15, 2015 - initial 
#> 

#==================================================
# FUNCTIONS
#==================================================
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {    
        return $psISE -ne $null;
    }
    catch {
        return $false;
    }
}
    
Function Get-ScriptPath {
    If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }

    # Makes debugging from ISE easier.
    if ($PSScriptRoot -eq "")
    {
        if (Test-IsISE)
        {
            $psISE.CurrentFile.FullPath
            #$root = Split-Path -Parent $psISE.CurrentFile.FullPath
        }
        else
        {
            $context = $psEditor.GetEditorContext()
            $context.CurrentFile.Path
            #$root = Split-Path -Parent $context.CurrentFile.Path
        }
    }
    else
    {
        #$PSScriptRoot
        $PSCommandPath
        #$MyInvocation.MyCommand.Path
    }
}

Function Format-ElapsedTime($ts) {
    $elapsedTime = ""
    if ( $ts.Minutes -gt 0 ){$elapsedTime = [string]::Format( "{0:00} min. {1:00}.{2:00} sec.", $ts.Minutes, $ts.Seconds, $ts.Milliseconds / 10 );}
    else{$elapsedTime = [string]::Format( "{0:00}.{1:00} sec.", $ts.Seconds, $ts.Milliseconds / 10 );}
    if ($ts.Hours -eq 0 -and $ts.Minutes -eq 0 -and $ts.Seconds -eq 0){$elapsedTime = [string]::Format("{0:00} ms.", $ts.Milliseconds);}
    if ($ts.Milliseconds -eq 0){$elapsedTime = [string]::Format("{0} ms", $ts.TotalMilliseconds);}
    return $elapsedTime
}

Function Format-DatePrefix{
    [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
	[string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
    $CombinedDateTime = "$LogDate $LogTime"
    return ($LogDate + " " + $LogTime)
}

Function Write-LogEntry{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false,Position=2)]
		[string]$Source = '',

        [parameter(Mandatory=$false)]
        [ValidateSet(0,1,2,3,4)]
        [int16]$Severity,

        [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
        [ValidateNotNullOrEmpty()]
        [string]$OutputLogFile = $Global:LogFilePath,

        [parameter(Mandatory=$false)]
        [switch]$Outhost = $Global:OutToHost
    )
    ## Get the name of this function
    [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

    [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
	[string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
	[int32]$script:LogTimeZoneBias = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes
	[string]$LogTimePlusBias = $LogTime + $script:LogTimeZoneBias
    #  Get the file name of the source script

    Try {
	    If ($script:MyInvocation.Value.ScriptName) {
		    [string]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
	    }
	    Else {
		    [string]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.Definition -Leaf -ErrorAction 'Stop'
	    }
    }
    Catch {
	    $ScriptSource = ''
    }
    
    
    If(!$Severity){$Severity = 1}
    $LogFormat = "<![LOG[$Message]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$ScriptSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$Severity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
    
    # Add value to log file
    try {
        Out-File -InputObject $LogFormat -Append -NoClobber -Encoding Default -FilePath $OutputLogFile -ErrorAction Stop
    }
    catch {
        Write-Host ("[{0}] [{1}] :: Unable to append log entry to [{1}], error: {2}" -f $LogTimePlusBias,$ScriptSource,$OutputLogFile,$_.Exception.ErrorMessage) -ForegroundColor Red
    }
    If($Outhost){
        If($Source){
            $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$Source,$Message)
        }
        Else{
            $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$ScriptSource,$Message)
        }

        Switch($Severity){
            0       {Write-Host $OutputMsg -ForegroundColor Green}
            1       {Write-Host $OutputMsg -ForegroundColor Gray}
            2       {Write-Warning $OutputMsg}
            3       {Write-Host $OutputMsg -ForegroundColor Red}
            4       {If($Global:Verbose){Write-Verbose $OutputMsg}}
            default {Write-Host $OutputMsg}
        }
    }
}

function Show-ProgressStatus
{
    <#
    .SYNOPSIS
        Shows task sequence secondary progress of a specific step
    
    .DESCRIPTION
        Adds a second progress bar to the existing Task Sequence Progress UI.
        This progress bar can be updated to allow for a real-time progress of
        a specific task sequence sub-step.
        The Step and Max Step parameters are calculated when passed. This allows
        you to have a "max steps" of 400, and update the step parameter. 100%
        would be achieved when step is 400 and max step is 400. The percentages
        are calculated behind the scenes by the Com Object.
    
    .PARAMETER Message
        The message to display the progress
    .PARAMETER Step
        Integer indicating current step
    .PARAMETER MaxStep
        Integer indicating 100%. A number other than 100 can be used.
    .INPUTS
         - Message: String
         - Step: Long
         - MaxStep: Long
    .OUTPUTS
        None
    .EXAMPLE
        Set's "Custom Step 1" at 30 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 100 -MaxStep 300
    
    .EXAMPLE
        Set's "Custom Step 1" at 50 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 150 -MaxStep 300
    .EXAMPLE
        Set's "Custom Step 1" at 100 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 300 -MaxStep 300
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$true)]
        [int]$Step,

        [Parameter(Mandatory=$true)]
        [int]$MaxStep,

        [string]$SubMessage,

        [int]$IncrementSteps,

        [switch]$Outhost
    )

    Begin{

        If($SubMessage){
            $StatusMessage = ("{0} [{1}]" -f $Message,$SubMessage)
        }
        Else{
            $StatusMessage = $Message

        }
    }
    Process
    {
        If($Script:tsenv){
            $Script:TSProgressUi.ShowActionProgress(`
                $Script:tsenv.Value("_SMSTSOrgName"),`
                $Script:tsenv.Value("_SMSTSPackageName"),`
                $Script:tsenv.Value("_SMSTSCustomProgressDialogMessage"),`
                $Script:tsenv.Value("_SMSTSCurrentActionName"),`
                [Convert]::ToUInt32($Script:tsenv.Value("_SMSTSNextInstructionPointer")),`
                [Convert]::ToUInt32($Script:tsenv.Value("_SMSTSInstructionTableSize")),`
                $StatusMessage,`
                $Step,`
                $Maxstep)
        }
        Else{
            Write-Progress -Activity "$Message ($Step of $Maxstep)" -Status $StatusMessage -PercentComplete (($Step / $Maxstep) * 100) -id 1
        }
    }
    End{
        Write-LogEntry $Message -Outhost:$Outhost
    }
}

Function Download-FileProgress{
    param(
         [Parameter(Mandatory=$false)]
         [Alias("Title")]
         [string]$Name,
         
         [Parameter(Mandatory=$true,Position=1)]
         [string]$Url,
         
         [Parameter(Mandatory=$true,Position=2)]
         [Alias("TargetDest")]
         [string]$TargetFile
     )
     Begin{
         ## Get the name of this function
         [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
     }
     Process
     {
         $ChildURLPath = $($url.split('/') | Select -Last 1)
 
         $uri = New-Object "System.Uri" "$url"
         $request = [System.Net.HttpWebRequest]::Create($uri)
         $request.set_Timeout(15000) #15 second timeout
         $response = $request.GetResponse()
         $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
         $responseStream = $response.GetResponseStream()
         $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
 
         $buffer = new-object byte[] 10KB
         $count = $responseStream.Read($buffer,0,$buffer.length)
         $downloadedBytes = $count
    
         If($Name){$Label = $Name}Else{$Label = $ChildURLPath}
 
         while ($count -gt 0)
         {
             $targetStream.Write($buffer, 0, $count)
             $count = $responseStream.Read($buffer,0,$buffer.length)
             $downloadedBytes = $downloadedBytes + $count
             #Write-Progress -activity "Downloading file '$($url.split('/') | Select -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes/1024)) / $totalLength)  * 100)
             Show-ProgressStatus -Message ("Downloading: {0} ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -f $Label) -Step ([System.Math]::Floor($downloadedBytes/1024)) -MaxStep $totalLength
         }
 
         Start-Sleep 3
 
         $targetStream.Flush()
         $targetStream.Close()
         $targetStream.Dispose()
         $responseStream.Dispose()
 
    }
    End{
         #Write-Progress -activity "Finished downloading file '$($url.split('/') | Select -Last 1)'"
        If($Name){$Label = $Name}Else{$Label = $ChildURLPath}
        Show-ProgressStatus -Message ("Finished downloading file: {0}" -f $Label) -Step $totalLength -MaxStep $totalLength
    }
    
 }
 
##* ==============================
##* VARIABLES
##* ==============================
# Use function to get paths because Powershell ISE and other editors have differnt results
$scriptPath = Get-ScriptPath
[string]$scriptDirectory = Split-Path $scriptPath -Parent
[string]$scriptName = Split-Path $scriptPath -Leaf
[string]$scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)

#Create Paths
$DefinitionsPath = Join-Path -Path $scriptDirectory -ChildPath 'Definitions'
$LogPath = Join-Path -Path $scriptDirectory -ChildPath 'Logs'

$Global:Verbose = $false
If($PSBoundParameters.ContainsKey('Debug') -or $PSBoundParameters.ContainsKey('Verbose')){
    $Global:Verbose = $PsBoundParameters.Get_Item('Verbose')
    $VerbosePreference = 'Continue'
    Write-Verbose ("[{0}] [{1}] :: VERBOSE IS ENABLED." -f (Format-DatePrefix),$scriptName)
}
Else{
    $VerbosePreference = 'SilentlyContinue'
}

#build log name
[string]$FileName = $scriptBaseName +'.log'
#build global log fullpath
$Global:LogFilePath = Join-Path $LogPath -ChildPath $FileName
Write-Host "logging to file: $LogFilePath" -ForegroundColor Cyan

# BUILD FOLDER STRUCTURE
#=======================================================
New-Item $SoftwarePath -type directory -ErrorAction SilentlyContinue | Out-Null
New-Item $RelativeLogPath -type directory -ErrorAction SilentlyContinue | Out-Null

#==================================================
# MAIN - DOWNLOAD 3RD PARTY SOFTWARE
#==================================================
## Load the System.Web DLL so that we can decode URLs
Add-Type -Assembly System.Web
$wc = New-Object System.Net.WebClient

# Proxy-Settings
#$wc.Proxy = [System.Net.WebRequest]::DefaultWebProxy
#$wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

#Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
#Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
#Get-Process "Openwith" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue


# Microsoft Security Essentials - X64 DOWNLOAD
#==================================================
Function Get-MSEDefinition {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$false)]
        [ValidateSet('Windows 7 (x86)', 'Windows 7 (x64)', 'Windows 7 (Both)','Windows 10 (x86)','Windows 10 (x64)','Windows 10 (Both)','All (x86)','All (x64)','All')]
        [string]$OSType = 'All'
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {    
        $Product = "Microsoft Security Essentials"
        [System.Uri]$DownloadURL = "http://go.microsoft.com"
        
        ## -------- BUILD DOWNLOAD LINKS ----------
        #get the appropiate url based on architecture and OS
        switch($OSType){
            'Windows 7 (x86)' {$ntOS="6.1";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&clcid=0x409&arch=x86&eng=0.0.0.0&avdelta=0.0.0.0&asdelta=0.0.0.0&prod=925A3ACA-C353-458A-AC8D-A7E5EB378092"}
            'Windows 7 (x64)' {$ntOS="6.1";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&clcid=0x409&arch=x64&eng=0.0.0.0&avdelta=0.0.0.0&asdelta=0.0.0.0&prod=925A3ACA-C353-458A-AC8D-A7E5EB378092"}

            'Windows 7 (Both)' {$ntOS="6.1";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&clcid=0x409&arch=x86&eng=0.0.0.0&avdelta=0.0.0.0&asdelta=0.0.0.0&prod=925A3ACA-C353-458A-AC8D-A7E5EB378092",
                                                 "$DownloadURL/fwlink/?LinkID=121721&clcid=0x409&arch=x64&eng=0.0.0.0&avdelta=0.0.0.0&asdelta=0.0.0.0&prod=925A3ACA-C353-458A-AC8D-A7E5EB378092"}

            'Windows 10 (x86)' {$ntOS="10.0";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&arch=x86"}
            'Windows 10 (x64)' {$ntOS="10.0";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&arch=x64"}

            'Windows 10 (Both)' {$ntOS="10.0";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&arch=x86",
                                                 "$DownloadURL/fwlink/?LinkID=121721&arch=x64"}

            'All' {$ntOS="All";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&clcid=0x409&arch=x86&eng=0.0.0.0&avdelta=0.0.0.0&asdelta=0.0.0.0&prod=925A3ACA-C353-458A-AC8D-A7E5EB378092",
                                    "$DownloadURL/fwlink/?LinkID=121721&clcid=0x409&arch=x64&eng=0.0.0.0&avdelta=0.0.0.0&asdelta=0.0.0.0&prod=925A3ACA-C353-458A-AC8D-A7E5EB378092",
                                    "$DownloadURL/fwlink/?LinkID=121721&arch=x86",
                                    "$DownloadURL/fwlink/?LinkID=121721&arch=x64"
                    }
            'All (x64)' {$ntOS="All";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&clcid=0x409&arch=x64&eng=0.0.0.0&avdelta=0.0.0.0&asdelta=0.0.0.0&prod=925A3ACA-C353-458A-AC8D-A7E5EB378092",
                                          "$DownloadURL/fwlink/?LinkID=121721&arch=x64"
                        }
            'All (x86)' {$ntOS="All";$DownloadLinks = "$DownloadURL/fwlink/?LinkID=121721&clcid=0x409&arch=x86&eng=0.0.0.0&avdelta=0.0.0.0&asdelta=0.0.0.0&prod=925A3ACA-C353-458A-AC8D-A7E5EB378092",
                                          "$DownloadURL/fwlink/?LinkID=121721&arch=x86"
                        }    
        }

        Write-LogEntry ("Parsing site: {0} for {1} {2} full definition files" -f $DownloadURL.AbsoluteUri,$OSType,$DefName) -Outhost
        ## -------- BUILD FOLDERS ----------
        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        ## -------- DOWNLOAD SOFTWARE ----------
        Foreach ($link in $DownloadLinks){
            #build Download link from Root URL (if Needed)
            $DownloadLink = $link
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost


            If($DownloadLink -match "prod=925A3ACA-C353-458A-AC8D-A7E5EB378092"){
                If($DownloadLink -match "arch=x64"){
                    $subpath = Join-Path -Path $DestinationPath -ChildPath "Win7\x64"
                    $ArchLabel = '(64-bit)'
                }
                Else{
                    $subpath = Join-Path -Path $DestinationPath -ChildPath "Win7\x86"
                    $ArchLabel = '(32-bit)'
                }
            }
            Else{
                If($DownloadLink -match "arch=x64"){
                    $subpath = Join-Path -Path $DestinationPath -ChildPath "Win10\x64"
                    $ArchLabel = '(64-bit)'
                }
                Else{
                    $subpath = Join-Path -Path $DestinationPath -ChildPath "Win10\x86"
                    $ArchLabel = '(32-bit)'
                }
            }
            New-Item -Path $subpath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            #find what arch the file is based on the integer 64
            $ExtensionType = [System.IO.Path]::GetExtension($fileName)

            Try{
                Write-LogEntry ("Attempting to download: [{0}]." -f $Filename) -Severity 1 -Source ${CmdletName} -Outhost

                Download-FileProgress -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                #$wc.DownloadFile($link, $destination) 
                Write-LogEntry ("Succesfully downloaded: {0} {1} to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            } 
            Catch {
                Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception) -Severity 3 -Source ${CmdletName} -Outhost
                $downloaded=$False
            }
        }
    }
}


Function Get-NISDefinition {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$false)]
        [string]$FolderPath = "NIS",
        [parameter(Mandatory=$false)]
        [ValidateSet('x86','x64','Both')]
        [string]$Arch = 'Both'
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {    
        $DefName = "Network-based exploit"
        [System.Uri]$DownloadURL = "http://go.microsoft.com"
        
        ## -------- BUILD DOWNLOAD LINKS ----------
        #get the appropiate url based on architecture and OS
        switch($Arch){
            'x86' {$DownloadLinks = "$DownloadURL/fwlink/?LinkID=187316&arch=x86&nri=true"}
            'x64' {$DownloadLinks = "$DownloadURL/fwlink/?LinkID=187316&arch=x64&nri=true"}

            'Both' {$DownloadLinks = "$DownloadURL/fwlink/?LinkID=187316&arch=x86&nri=true",
                                                 "$DownloadURL/fwlink/?LinkID=187316&arch=x64&nri=true"}
        }

        Write-LogEntry ("Parsing site: {0} for {1} {2} full definition files" -f $DownloadURL.AbsoluteUri,$OSType,$DefName) -Outhost
        ## -------- BUILD FOLDERS ----------
        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        ## -------- DOWNLOAD SOFTWARE ----------
        Foreach ($link in $DownloadLinks){
            #build Download link from Root URL (if Needed)
            $DownloadLink = $link
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

            $Filename = 'nis_full.exe'
            If($DownloadLink -match "arch=x64"){
                $subpath = Join-Path -Path $DestinationPath -ChildPath "$FolderPath\x64"
                $ArchLabel = '64-bit'
            }
            Else{
                $subpath = Join-Path -Path $DestinationPath -ChildPath "$FolderPath\x86"
                $ArchLabel = '32-bit'
            }
            New-Item -Path $subpath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            Try{
                Write-LogEntry ("Attempting to download: [{0}]." -f $Filename) -Severity 1 -Source ${CmdletName} -Outhost

                Download-FileProgress -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                #$wc.DownloadFile($link, $destination) 
                Write-LogEntry ("Succesfully downloaded: {0} {1} to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            } 
            Catch {
                Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception) -Severity 3 -Source ${CmdletName} -Outhost
                $downloaded=$False
            }
        }
    }
}

# McAfee DAT V2 Virus Definition - DOWNLOAD
#==================================================
Function Get-DATDefinition {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$false)]
        [string]$FolderPath = "McAfee",
        [parameter(Mandatory=$false)]
        [ValidateSet('x86','x64','Both')]
        [string]$Arch = 'Both'
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {    
        $DefName = "McAfee DAT"
        $SourceURL = Invoke-WebRequest "http://update.nai.com/products/commonupdater/gdeltaavv.ini"
       
        ## -------- GET VERSION ----------
        [array]$A=$SourceURL -split "`r`n"
        $CurrentVersion=$A[3].Split('=')[1]

        
        ## -------- BUILD DOWNLOAD LINKS ----------
        [System.Uri]$DownloadURL="http://update.nai.com/products/datfiles/4.x/nai/$($CurrentVersion)xdat.exe"
        #$datfile = (invoke-webrequest $DownloadURL).Content.RawContent

        ## -------- BUILD FOLDERS ----------
        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        ## -------- DOWNLOAD SOFTWARE ----------
        Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadURL.AbsoluteUri) -Severity 1 -Source ${CmdletName} -Outhost

        $filename = $($CurrentVersion) + "xdat.exe"
        $destination = $DestinationPath + "\" + $filename

        If (Test-Path "$destination" -ErrorAction SilentlyContinue){
            $LogComment = $($CurrentVersion) + "xdat.exe is already downloaded"
            Write-LogEntry $LogComment -Source ${CmdletName} -Outhost
        } Else {
            Try{
                Write-LogEntry ("Attempting to download: [{0}]." -f $Filename) -Severity 1 -Source ${CmdletName} -Outhost

                Download-FileProgress -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                #$wc.DownloadFile($link, $destination) 
                Write-LogEntry ("Succesfully downloaded: {0} to [{1}]" -f $Product,$destination) -Severity 0 -Source ${CmdletName} -Outhost
            } 
            Catch {
                Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception) -Severity 3 -Source ${CmdletName} -Outhost
            }
        }

    }
}


