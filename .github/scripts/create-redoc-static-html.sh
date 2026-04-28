#!/bin/bash
set -e

currentFolder="$(pwd)"
publicFolder="$currentFolder/public"

findAllFiles() {
    local -n resultRef=$1

    while IFS= read -r -d '' dir; do
        rel_dir="${dir#$currentFolder/}"
        resultRef["$rel_dir"]="openapi"
    done < <(find "$currentFolder" -type f -name "openapi.yaml" -print0 | xargs -0 -n1 dirname -z | sort -zu)

    while IFS= read -r -d '' file; do
        rel_file="${file#$currentFolder/}"
        resultRef["$rel_file"]="pdf"
    done < <(find "$currentFolder" -type f -name "*.pdf" -print0 | sort -z)

    while IFS= read -r -d '' file; do
        rel_file="${file#$currentFolder/}"
        resultRef["$rel_file"]="xlsx"
    done < <(find "$currentFolder" -type f -name "*.xlsx" -print0 | sort -z)
}

loadStaticHtmlToFolder() {
    local folder="$1"

    echo "Creating folder \"$publicFolder/$folder\""
    mkdir -p "$publicFolder/$folder"

    echo "Bundling OpenAPI spec: \"$currentFolder/$folder/openapi.yaml\""
    npx @redocly/cli@latest bundle "$currentFolder/$folder/openapi.yaml" -o "$publicFolder/$folder/openapi-combined.yaml" --ext yaml

    echo "Building docs: \"$currentFolder/$folder/openapi.yaml\""
    npx @redocly/cli@latest build-docs "$currentFolder/$folder/openapi.yaml" -o "$publicFolder/$folder/index.html" --theme.openapi.downloadDefinitionUrl="openapi-combined.yaml"
}

generateHighLevelIndex() {
    local indexFile="$publicFolder/index.html"
    echo "<!DOCTYPE html>
<html>
<head>
    <meta charset=\"UTF-8\">
    <title>Less Than Truckload API Documentation</title>
</head>
<style>
   body {
        font-family: Arial, sans-serif;
        margin: 20px;
    }
    p {
        max-width: 720px;
        line-height: 1.6;
    }
    img.logo {
        max-height: 100px;
        margin-top: 10px;
        margin-bottom: 10px;
    }
    .tree {
        list-style-type: none;
        padding-left: 0;
    }
    .tree ul {
        list-style-type: none;
        padding-left: 20px;
        margin: 0;
    }
    .tree li {
        margin: 3px 0;
        position: relative;
    }
    .folder {
        font-weight: bold;
        color: #333;
        cursor: pointer;
        user-select: none;
    }
    .folder::before {
        content: '📁 ';
        margin-right: 5px;
    }
    .folder.collapsed::before {
        content: '📂 ';
    }
    .file-link {
        text-decoration: none;
        padding: 2px 4px;
        border-radius: 3px;
        transition: background-color 0.2s;
    }
    .file-link:hover {
        background-color: #f0f0f0;
    }
    .pdf-link {
        color: #d9534f;
    }
    .pdf-link::before {
        content: '📄 ';
        margin-right: 5px;
    }
    .xlsx-link {
        color: #5cb85c;
    }
    .xlsx-link::before {
        content: '📊 ';
        margin-right: 5px;
    }
    .openapi-link {
        color: #5bc0de;
    }
    .openapi-link::before {
        content: '📋 ';
        margin-right: 5px;
    }
    .toggle {
        display: inline-block;
        width: 16px;
        text-align: center;
        cursor: pointer;
        user-select: none;
        margin-right: 3px;
    }
    .hidden {
        display: none;
    }
</style>
<body>
    <img class=\"logo\" src=\"images/DSDC-LTL.svg\" alt=\"Company Logo\">
    <p>Supported by the Digital Standard Development Council's (DSDC) Digital LTL Council, these API standards help organizations modernize LTL workflows through standardized, open, and scalable integration.</p>
    <h1>Less Than Truckload API Documentation</h1>
    <ul class=\"tree\" id=\"root\">" > "$indexFile"

    # Sort all paths for processing
    local sortedPaths=()
    for path in "${!allFiles[@]}"; do
        sortedPaths+=("$path")
    done
    IFS=$'\n' sortedPaths=($(sort <<< "${sortedPaths[*]}"))
    unset IFS

    # Copy PDF and XLSX files
    for path in "${sortedPaths[@]}"; do
        local fileType="${allFiles[$path]}"
        if [[ "$fileType" == "pdf" || "$fileType" == "xlsx" ]]; then
            local fileDir=$(dirname "$path")
            mkdir -p "$publicFolder/$fileDir"
            cp "$currentFolder/$path" "$publicFolder/$path"
        fi
    done

    # Build complete tree structure
    declare -A treeNodes
    declare -a topLevel
    
    for path in "${sortedPaths[@]}"; do
        IFS='/' read -ra parts <<< "$path"
        local currentPath=""
        
        for ((i=0; i<${#parts[@]}-1; i++)); do
            local part="${parts[$i]}"
            if [[ -n "$currentPath" ]]; then
                currentPath="$currentPath/$part"
            else
                currentPath="$part"
            fi
            
            if [[ -z "${treeNodes[$currentPath]}" ]]; then
                treeNodes["$currentPath"]="folder"
                
                if [[ $i -eq 0 ]]; then
                    topLevel+=("$currentPath")
                fi
            fi
        done
        
        treeNodes["$path"]="${allFiles[$path]}"
    done

    IFS=$'\n' topLevel=($(sort -u <<< "${topLevel[*]}"))
    unset IFS

    printTree() {
        local prefix="$1"
        local indent="$2"
        
        local items=()
        for path in "${sortedPaths[@]}"; do
            if [[ -z "$prefix" ]]; then
                IFS='/' read -ra parts <<< "$path"
                local firstPart="${parts[0]}"
                items+=("$firstPart")
            elif [[ "$path" == "$prefix"* ]]; then
                local remainder="${path#$prefix/}"
                if [[ "$remainder" != */* ]]; then
                    items+=("$path")
                else
                    IFS='/' read -ra parts <<< "$remainder"
                    local nextPart="$prefix/${parts[0]}"
                    items+=("$nextPart")
                fi
            fi
        done
        
        IFS=$'\n' items=($(sort -u <<< "${items[*]}"))
        unset IFS
        
        for item in "${items[@]}"; do
            local nodeType="${treeNodes[$item]}"
            
            if [[ "$nodeType" == "folder" ]]; then
                IFS='/' read -ra parts <<< "$item"
                local folderName="${parts[-1]}"
                
                echo "${indent}<li>" >> "$indexFile"
                echo "${indent}    <span class=\"toggle\" onclick=\"toggleFolder(this)\">▼</span>" >> "$indexFile"
                echo "${indent}    <span class=\"folder\">$folderName</span>" >> "$indexFile"
                echo "${indent}    <ul>" >> "$indexFile"
                
                printTree "$item" "$indent    "
                
                echo "${indent}    </ul>" >> "$indexFile"
                echo "${indent}</li>" >> "$indexFile"
                
            elif [[ "$nodeType" == "openapi" ]]; then
                if [[ -f "$publicFolder/$item/index.html" ]]; then
                    IFS='/' read -ra parts <<< "$item"
                    local fileName="${parts[-1]}"
                    echo "${indent}<li><a class=\"file-link openapi-link\" href=\"$item/index.html\">$fileName (OpenAPI)</a></li>" >> "$indexFile"
                fi
                
            elif [[ "$nodeType" == "pdf" ]]; then
                IFS='/' read -ra parts <<< "$item"
                local fileName="${parts[-1]}"
                echo "${indent}<li><a class=\"file-link pdf-link\" href=\"$item\" target=\"_blank\">$fileName</a></li>" >> "$indexFile"

            elif [[ "$nodeType" == "xlsx" ]]; then
                IFS='/' read -ra parts <<< "$item"
                local fileName="${parts[-1]}"
                echo "${indent}<li><a class=\"file-link xlsx-link\" href=\"$item\" target=\"_blank\">$fileName</a></li>" >> "$indexFile"
            fi
        done
    }

    printTree "" "        "

    echo "    </ul>
    <script>
        function toggleFolder(toggle) {
            const li = toggle.parentElement;
            const ul = li.querySelector('ul');
            if (ul) {
                ul.classList.toggle('hidden');
                toggle.textContent = ul.classList.contains('hidden') ? '▶' : '▼';
            }
        }
        
        document.addEventListener('DOMContentLoaded', function() {
            const folders = document.querySelectorAll('.folder');
            folders.forEach(folder => {
                folder.addEventListener('dblclick', function(e) {
                    const toggle = this.previousElementSibling;
                    if (toggle && toggle.classList.contains('toggle')) {
                        toggleFolder(toggle);
                    }
                });
            });
        });
    </script>
</body>
</html>" >> "$indexFile"
    echo "Created high level index at \"$indexFile\""
}

copyImages() {
    echo "Copying images..."
    mkdir -p "$publicFolder/images"
    cp "$currentFolder/images/DSDC-LTL.svg" "$publicFolder/images/"
}

mainProcess() {
    echo "Removing existing public folder..."
    rm -rf "$publicFolder"

    declare -A allFiles
    findAllFiles allFiles

    for path in "${!allFiles[@]}"; do
        if [[ "${allFiles[$path]}" == "openapi" ]]; then
            echo "Processing OpenAPI directory: \"$path\""
            loadStaticHtmlToFolder "$path"
        fi
    done

    generateHighLevelIndex
    copyImages
}

mainProcess
