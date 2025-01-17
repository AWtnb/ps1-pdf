﻿
<# ==============================

cmdlets for treating PDF

                encoding: utf8bom
============================== #>

function Use-TempDir {
    <#
    .NOTES
    > Use-TempDir {$pwd.Path}
    Microsoft.PowerShell.Core\FileSystem::C:\Users\~~~~~~ # includes PSProvider
    > Use-TempDir {$pwd.ProviderPath}
    C:\Users\~~~~~~ # literal path without PSProvider
    #>
    param (
        [ScriptBlock]$script
    )
    $tmp = $env:TEMP | Join-Path -ChildPath $([System.Guid]::NewGuid().Guid)
    New-Item -ItemType Directory -Path $tmp | Push-Location
    "working on tempdir: {0}" -f $tmp | Write-Host -ForegroundColor DarkBlue
    $result = $null
    try {
        $result = Invoke-Command -ScriptBlock $script
    }
    catch {
        $_.Exception.ErrorRecord | Write-Error
        $_.ScriptStackTrace | Write-Host
    }
    finally {
        Pop-Location
        $tmp | Remove-Item -Recurse
    }
    return $result
}

class PyPdf {
    [string]$pyPath
    PyPdf([string]$pyFile) {
        $this.pyPath = $PSScriptRoot | Join-Path -ChildPath "python\pdf" | Join-Path -ChildPath $pyFile
    }
    RunCommand([string[]]$params){
        $fullParams = (@("-B", $this.pyPath) + $params) | ForEach-Object {
            if ($_ -match " ") {
                return ($_ | Join-String -DoubleQuote)
            }
            return $_
        }
        Start-Process -Path python.exe -Wait -ArgumentList $fullParams -NoNewWindow
    }
}


function Invoke-PdfOverlayWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[string]$overlayPdf
    )
    begin {}
    process {
        $pdfFileObj = Get-Item -LiteralPath $inputObj
        if ($pdfFileObj.Extension -ne ".pdf") {
            Write-Error "Non-pdf file!"
            return
        }
        $overlayPath = (Get-Item -LiteralPath $overlayPdf).FullName
        $py = [PyPdf]::new("overlay.py")
        $py.RunCommand(@($pdfFileObj.FullName, $overlayPath))
    }
    end {}
}

function Invoke-PdfFilenameWatermarkWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[int]$startIdx = 1
        ,[switch]$countThrough
    )
    begin {
        $pdfs = @()
    }
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -eq ".pdf") {
            $pdfs += $file
        }
    }
    end {
        $py = [PyPdf]::new("overlay_filename.py")
        $mode = ($countThrough)? "through" : "single"
        Use-TempDir {
            $in = New-Item -Path ".\in.txt"
            $pdfs.Fullname | Out-File -FilePath $in.FullName -Encoding utf8NoBOM
            $py.RunCommand(@($in.FullName, $startIdx, $mode))
        }
    }
}


function pyGenSearchPdf {
    param (
        [string]$outName = "search_"
        ,[int]$start = 1
    )
    $files = $input | Where-Object {$_.Extension -eq ".pdf"}
    $orgDir = $pwd.ProviderPath
    Use-TempDir {
        $tempDir = $pwd.ProviderPath
        $files | Copy-Item -Destination $tempDir
        Get-ChildItem "*.pdf" | Invoke-PdfUnspreadWithPython
        Get-ChildItem "*.pdf" | Where-Object { $_.BaseName -notmatch "unspread$" } | Remove-Item
        Get-ChildItem "*_unspread.pdf" | Rename-Item -NewName { ($_.BaseName -replace "_unspread$") + $_.Extension }
        Get-ChildItem "*.pdf" | Invoke-PdfFilenameWatermarkWithPython -countThrough -startIdx $start
        Get-ChildItem "wm*.pdf" | Invoke-PdfConcWithPython -outName $outName
        Get-ChildItem | Where-Object { $_.BaseName -eq $outName } | Move-Item -Destination $orgDir
    }
}

function Invoke-PdfConcWithPython {
    param (
        [string]$outName = "conc"
    )

    $pdfs = @($input | Get-Item | Where-Object Extension -eq ".pdf")
    if ($pdfs.Count -le 1) {
        return
    }

    $dirs = @($pdfs | ForEach-Object {$_.Directory.Fullname} | Sort-Object -Unique)
    $outDir = ($dirs.Count -gt 1)? $pwd.ProviderPath : $dirs[0]
    $outPath = $outDir | Join-Path -ChildPath "$($outName).pdf"

    if (Test-Path $outPath) {
        "'{0}.pdf' already exists on '{1}'!" -f $outName, $outDir | Write-Error
        return
    }

    $py = [PyPdf]::new("conc.py")

    Use-TempDir {
        $paths = New-Item -Path ".\paths.txt"
        $pdfs.Fullname | Out-File -Encoding utf8NoBOM -FilePath $paths
        $py.RunCommand(@($paths, $outPath))
    }

}
Set-Alias pdfConcPy Invoke-PdfConcWithPython


function Invoke-PdfZipToDiffWithPython {
    param (
        [string]
        $oddFile,
        [string]
        $evenFile,
        [string]$outName = "outdiff"
    )
    $odd = Get-Item -LiteralPath $oddFile
    $even = Get-Item -LiteralPath $evenFile
    if (($odd.Extension -ne ".pdf") -or ($even.Extension -ne ".pdf")) {
        "non-pdf file!" | Write-Error
        return
    }
    $outPath = $PWD.ProviderPath | Join-Path -ChildPath "$($outName).pdf"
    $py = [PyPdf]::new("zip_to_diff.py")
    $py.RunCommand(@($odd.FullName, $even.FullName, $outPath))
}

function Invoke-PdfToImageWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj,
        [int]$dpi = 300
    )
    begin {}
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("to_image.py")
        $py.RunCommand(@($file.FullName, $dpi))
    }
    end {}
}
Set-Alias pdfImagePy Invoke-PdfToImageWithPython


function Invoke-PdfCompressWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
    )
    begin {
    }
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("compress.py")
        $py.RunCommand(@($file.FullName))
    }
    end {}
}
Set-Alias pdfCompressPy Invoke-PdfCompressWithPython

function Invoke-PdfExtractWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[int]$from = 1
        ,[int]$to = -1
        ,[string]$outName = ""
    )
    begin {
        $files = @()
    }
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -eq ".pdf") {
            $files += $file
        }
    }
    end {
        $files | ForEach-Object {
            $py = [PyPdf]::new("extract.py")
            $py.RunCommand(@($_.Fullname, $from, $to, $outName))
        }
    }
}
Set-Alias pdfExtractPy Invoke-PdfExtractWithPython

function Invoke-PdfExtractStepWithPython {
    <#
    .EXAMPLE
        Invoke-PdfExtractStepWithPython -path hoge.pdf -froms 1,4,6
    #>
    param (
        [string]
        $path
        ,[int[]]$froms
    )
    $file = Get-Item -LiteralPath $path
    if ($file.Extension -ne ".pdf") {
        return
    }
    for ($i = 0; $i -lt $froms.Count; $i++) {
        $f = $froms[$i]
        $t = ($i + 1 -eq $froms.Count)? -1 : $froms[($i + 1)] - 1
        Invoke-PdfExtractWithPython -inputObj $file.FullName -from $f -to $t
    }
}

function Invoke-PdfRotateWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[ValidateSet(90, 180, 270)][int]$clockwise = 180
    )
    begin {}
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("rotate.py")
        $py.RunCommand(@($file.Fullname, $clockwise))
    }
    end {}
}
Set-Alias pdfRotatePy Invoke-PdfRotateWithPython

function Invoke-PdfSpreadWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[switch]$singleTopPage
        ,[switch]$backwards
        ,[switch]$vertical
    )
    begin {}
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("spread.py")
        $params = @($file.FullName)
        if ($singleTopPage) {
            $params += "--singleTopPage"
        }
        if ($backwards) {
            $params += "--backwards"
        }
        if ($vertical) {
            $params += "--vertical"
        }
        $py.RunCommand($params)
    }
    end {}
}
Set-Alias pdfSpreadPy Invoke-PdfSpreadWithPython



function pyGenPdfSpreadImg {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[switch]$singleTopPage
        ,[switch]$vertical
        ,[int]$dpi = 300
    )
    $file = Get-Item -LiteralPath $inputObj
    if ($file.Extension -ne ".pdf") {
        return
    }
    Invoke-PdfSpreadWithPython -inputObj $file -singleTopPage:$singleTopPage -vertical:$vertical
    $spreadFilePath = $file.FullName -replace "\.pdf$", "_spread.pdf" | Get-Item
    Invoke-PdfToImageWithPython -inputObj $spreadFilePath -dpi $dpi
}

function Invoke-PdfUnspreadWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[switch]$vertical
        ,[switch]$singleTop
        ,[switch]$singleLast
        ,[switch]$backwards
    )
    begin {}
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("unspread.py")
        $params = @($file.FullName)
        if ($vertical) {
            $params += "--vertical"
        }
        if ($singleTop) {
            $params += "--singleTop"
        }
        if ($singleLast) {
            $params += "--singleLast"
        }
        if ($backwards) {
            $params += "--backwards"
        }
        $py.RunCommand($params)
    }
    end {}
}
Set-Alias pdfUnspreadPy Invoke-PdfUnspreadWithPython

function Invoke-PdfTrimGalleyMarginWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[float]$marginHorizontalRatio = 0.08
        ,[float]$marginVerticalRatio = 0.08
    )
    begin {}
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("trim.py")
        $py.RunCommand(@($file.Fullname, $marginHorizontalRatio, $marginVerticalRatio))
    }
    end {}
}

Set-Alias pdfTrimMarginPy Invoke-PdfTrimGalleyMarginWithPython


function Invoke-PdfSwapWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[string]$newPdf
        ,[int]$swapStartPage = 1
        ,[int]$swapPageLength = 1
    )
    begin {}
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -eq ".pdf") {
            $py = [PyPdf]::new("swap.py")
            $py.RunCommand(@($file.Fullname, (Get-Item -LiteralPath $newPdf).FullName, $swapStartPage, $swapPageLength))
        }
    }
    end {}
}

function Invoke-PdfInsertWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[string]$newPdf
        ,[int]$insertAfter = 1
        ,[string]$outName = ""
    )
    begin {}
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("insert.py")

        $py.RunCommand(@($file.Fullname, $newPdf, $insertAfter, $outName))
    }
    end {}
}
Set-Alias pdfInsertPy Invoke-PdfInsertWithPython

function Invoke-PdfZipPagesWithPython {
    param (
        [string]
        $oddFile,
        [string]
        $evenFile,
        [string]$outName = "outzip"
    )
    $odd = Get-Item -LiteralPath $oddFile
    $even = Get-Item -LiteralPath $evenFile
    if (($odd.Extension -ne ".pdf") -or ($even.Extension -ne ".pdf")) {
        "non-pdf file!" | Write-Error
        return
    }
    $outPath = $PWD.ProviderPath | Join-Path -ChildPath "$($outName).pdf"
    $py = [PyPdf]::new("zip_pages.py")
    $py.RunCommand(@($odd.Fullname, $even.Fullname, $outPath))
}

function Invoke-PdfUnzipPagesWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[switch]$evenPages
    )
    begin {
        $opt = ($evenPages)? "--evenPages" : ""
    }
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("unzip_pages.py")
        $py.RunCommand(@($file.FullName, $opt))
    }
    end {}
}

function Invoke-PdfSplitPagesWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
    )
    begin {
    }
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("split.py")
        $py.RunCommand(@($file.FullName))
    }
    end {}
}
Set-Alias pdfSplitPagesPy Invoke-PdfSplitPagesWithPython

function Invoke-PdfTextExtractWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
    )
    begin {
    }
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("get_text.py")
        $py.RunCommand(@($file.FullName))
    }
    end {}
}

function Invoke-PdfTitleMetadataModifyWithPython {
    param (
        [parameter(ValueFromPipeline)]
        $inputObj
        ,[string]$title = "Title"
        ,[switch]$preserveUntouchedData
    )
    begin {
    }
    process {
        $file = Get-Item -LiteralPath $inputObj
        if ($file.Extension -ne ".pdf") {
            return
        }
        $py = [PyPdf]::new("modify_metadata.py")
        $py.RunCommand(@($file.FullName, $title, $preserveUntouchedData))
    }
    end {}
}