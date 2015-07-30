Param(
  [Parameter(Position=0)]
  [string]$index,
  [Parameter(Mandatory=$false,ValueFromRemainingArguments=$true)]
  [String[]]$rgs
)
$gitDir = ''
$workTree = ''
$baseDir = $null

function Get-BaseDir {
    if( $script:baseDir ) {
        return $script:baseDir 
    }
    
    $prefix = $pwd

    do {
        $lastpath = $prefix
        $folders = dir "$prefix\.git*" -Attributes hidden,directory 
        if( $folders )  {
            $script:baseDir = $prefix
            return $script:baseDir 
        }
        $prefix = (resolve-path "$prefix\..").Path
    } Until ($lastpath -eq $prefix)
    return $null;
}

function Get-Repositories {
    $prefix = $pwd
    $lastPath= $pwd

    $baseDir = get-basedir
    if( -not $baseDir )  {
         write-error "Unable to find git repository base (any of .git, git-*...)"
         exit;
    }

    $result = @()
    $folders = (dir "$baseDir\.git-*" -Attributes hidden,directory)
    if ($folders ) {
        $result = ($folders).Name.SubString(5)
    }
    $singleDir = (dir "$baseDir\.git" -Attributes hidden,directory -ea silentlycontinue) 
    if( $singleDir ) {
        $result += "."
    }
    return $result;
    
}

function Get-GitBase {
  Param( [Parameter(Position=0)] [string]$index )

    $baseDir = get-basedir
    if( -not $baseDir )  {
         write-error "Unable to find git repository base (any of .git, git-*...)"
         exit;
    }
    if( (($index -eq ".") -or ($index -eq ""))  ) {
        if(test-path "$baseDir\.git" ) {
            $script:gitDir = (resolve-path "$baseDir\.git" ).Path
            $script:workTree = $baseDir
            return @("--git-dir=$($script:gitdir)", "--work-tree=$($script:worktree)" );
        }
         write-error "Unable to find .git folder"
         exit;
    }
    
    if( test-path "$baseDir\.git-$index" )  {
        $script:gitDir = (resolve-path "$baseDir\.git-$index" ).Path
        $script:workTree = $baseDir
        return @("--git-dir=$($script:gitdir)", "--work-tree=$($script:worktree)" );
    }
    
    write-error "Unable to find .git-$index folder" 
    exit;
}

function Flatten {
    Param(  [Parameter(Position=0)][object[]]$rgs )
    
    foreach( $i in $rgs ) {
        if( $i ) {
            if ( $i.Count -gt 1 ) {
                Flatten $i
            } else {
                $i
            }
        }
    }
}

function CallGit {
    Param( 
        [Parameter(Position=0)][string]$index ,
        [Parameter(Position=1)][String[]]$rgs,
        [Parameter(Mandatory=$false,ValueFromRemainingArguments=$true)][object[]]$moreargs
    )
    $a = $(Get-GitBase $index)  
    
    $a += Flatten $rgs
    $a += Flatten $moreargs
    
 
    $a= ($a |% { "`"$_`"" }  )
    
    
    #write-host $a.length $a.count
    write-debug "git.exe $a"
    
    #$r = (&git $a)
    #write-host $r
    #return $r
    return git.exe $a
}

function Get-RepositoryName {
    Param( [Parameter(Position=0)] [string]$index )
    
    $remotes = CallGit $index remote show -n
    if( $remotes ) {
        if( $remotes.count -gt 1 ) {
             if( (CallGit $index branch -vv ) -match "\[(.*)\/.*\]"  ) { 
                $remotes = $matches[1]
             }
        } 
    
        $url = ((CallGit $index remote show $remotes -n)  -match "push.*url")[0].substring(13)
        return "$remotes = $url"
    }
    return "(no remote set)"
}

function Get-UntrackedFilesImpl {
    Param( [Parameter(Position=0)] [string]$index )
    $untracked = ((CallGit $index status --porcelain) |? { $_.startswith("??") } )
    if( $untracked ) {
        return $untracked.SubString(3) 
    }
}

function Indent-Text {
    [CmdletBinding()]
    Param( [Parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)][string[]]$texts ) 
    PROCESS {
        foreach( $text in $texts ) {
            "  $text"
        }
    }
}

function Write-RepoName {
    Param( [Parameter(Position=0)] [string]$index )
    
    write-host -fore green "$($index) " -nonewline 
    write-host ": " -nonewline 
    write-host -fore cyan "$(get-repositoryname $index)" 

}

function Write-WithColor {
    [CmdletBinding()]
    Param( [Parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)][string[]]$texts ) 
    PROCESS {
        foreach( $text in $texts ) {
            if( $text -like "*Untracked files not listed (use -u option to show untracked files)*" ) {
             #ignore.
            } elseif ( $text -like "*new file:*" ) {
                write-host -fore green $text
            } elseif( $text -like "*modified:*" ) {
                write-host -fore yellow $text
            } elseif( $text -like "*deleted:*" ) {
                write-host -fore red $text
            } else {
                write-host -fore gray $text
            }
        }
    }
}

function Write-UntrackedFiles {
    [CmdletBinding()]
    Param( [Parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)][String[]]$untracked ) 
    BEGIN {
        $i = $true
    }
    PROCESS {
        if( ($untracked) -and ($untracked.Length -gt 0 ) ) {
           
           if($i) {
            write-host -fore cyan "Untracked files:"
            write-host '  (use "gitx # add <file>..." to include in what will be committed)'
            write-host ''
            $i = $false;
           }
           
            $untracked |% {  write-host -fore red "        $_"  } 
        }
    }
}

function Get-UntrackedFiles { 
    $untracked = $null
    
    (Get-Repositories) |% {
        if( $untracked ) {
            $files = get-untrackedfilesimpl $_ 
            $untracked = (Compare-Object $untracked $files -PassThru -IncludeEqual -ExcludeDifferent)
        } else {
            $untracked = get-untrackedfilesimpl $_ 
            $files = (dir "$(Get-BaseDir)\.git*" -attributes directory,hidden).Name |% {"$_/" }
            $untracked = $untracked |? { $files -notcontains $_ }
        }
    }
    return $untracked
}


function GitStatus {
    Param( [String[]]$rgs ) 
    (Get-Repositories) |% {
        write-reponame $_
        (CallGit $_ status $rgs --untracked-files=no ) | Indent-text | Write-WithColor 
        write-host ""
    }
    Get-UntrackedFiles | Write-UntrackedFiles 
}

function GitCommit {
    Param( [String[]]$rgs ) 
    (Get-Repositories) |% {
        write-reponame $_
        (CallGit $_ commit --untracked-files=no $rgs ) | Indent-text | Write-WithColor 
        write-host ""
    }
    Get-UntrackedFiles | Write-UntrackedFiles 
}

function GitClone {
    Param( [String[]]$rgs ) 
    $baseDir = Get-BaseDir 
    if( $baseDir ) {
    
        pushd $baseDir
        $null = mkdir .\.gittmp
        pushd .\.gittmp
        $cloned = (& cmd /c "git.exe $rgs --separate-git-dir=$basedir\.git-$index  2>&1")
        if( "$cloned" -match "'(.*)'" ) {
            $project = $matches[1]
        }
        write-host -fore white $cloned 
        rm -force "$project\.git"
        move -force "$project\*" $basedir 
        popd 
        
        rm -recurse -force .gittmp
        popd
        
        return;
    } else {
        # make a new repository right here.
        # git --git-dir=.git-$index  $rgs  | Indent-Text | Write-WithColor
        
        $null =mkdir .\.gittmp
        
        $cloned = (& cmd /c "git.exe $rgs --separate-git-dir=.gittmp\.git-$index 2>&1")
        write-host -fore white $cloned
        
        if( "$cloned" -match "'(.*)'" ) {
            $project = $matches[1]
        }
        
        rm -force "$project\.git"
        move -force ".gittmp\.git-$index" "$project\.git-$index"
        
        rm -recurse -force .gittmp
        
        return;
    }
}

function GitInit {
    Param( [String[]]$rgs ) 
    $baseDir = Get-BaseDir 
    if( $baseDir ) {
        git.exe --git-dir=$baseDir\.git-$index --work-tree=$baseDir $rgs  | Indent-Text | Write-WithColor
        return;
    } else {
        # make a new repository right here.
        git.exe --git-dir=.git-$index --work-tree=. $rgs  | Indent-Text | Write-WithColor
        return;
    }
}

function GitAll {
    Param( 
        [Parameter(Mandatory=$true)][String] $cmd,
        [String[]]$rgs 
    ) 
    (Get-Repositories) |% {
        write-reponame $_
        CallGit $_ $cmd $rgs 
        write-host ""
    }
}


if( $index ) {

    if( -not $rgs ) {
       $rgs = @()
    }


    Switch( $index )  {
        "status" { return GitStatus $rgs }
        "commit" { return GitCommit $rgs }
        "diff"   { return GitAll "diff" $rgs }
        "log"    { return GitAll "log" $rgs }
        "push"    { return GitAll "push" $rgs }
        "pull"    { return GitAll "pull" $rgs }
    }

    # Special Cases where we need to intervene
    Switch( $rgs[0] ) {
        "init"    { return GitInit $rgs }
        "clone"   { return GitClone $rgs }
    }
    $base = (Get-GitBase $index)
    
    write-reponame $index
    if( ( $rgs[0] -eq "commit" ) -or ($rgs[0] -eq "status") ) {

        CallGit $index $rgs "--untracked-files=no"  | Indent-Text | Write-WithColor
        Get-UntrackedFiles | Write-UntrackedFiles 
        return;
    }

    # for everything else just pass it thru as long as they have a valid base.

    CallGit $index $rgs  | Indent-Text | Write-WithColor
    return;
}

## find all .git- dirs
$repos = (Get-Repositories)
if ( $repos ) {
    write-host -fore white "repositories present:"
    $repos |% { 
        write-host "  " -nonewline
        Write-RepoName $_ 
    }
}
