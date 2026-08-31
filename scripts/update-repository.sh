#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

required_commands=(apt-ftparchive xz)
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 69
  fi
done

download_dir="${PACKAGE_DOWNLOAD_DIR:-$repository_root/downloads}"

# Release assets must land on disk before the pool is scanned, otherwise the
# generated indexes would omit every manifest package.
if [[ "${SKIP_PACKAGE_FETCH:-0}" != "1" ]]; then
  PACKAGE_DOWNLOAD_DIR="$download_dir" "$repository_root/scripts/fetch-packages.sh"
fi

work_dir="$(mktemp -d "$repository_root/.repo-build.XXXXXX")"
site_dir="$work_dir/site"
index_dir="$work_dir/indexes"
pool_dir="$work_dir/pool"
output_dir="$repository_root/_site"
mkdir -p "$site_dir" "$index_dir" "$pool_dir/debs"
trap 'rm -rf -- "$work_dir"' EXIT

# The published pool merges the tracked packages with the ones downloaded from
# the manifest so both kinds of package share a single relative Filename prefix.
shopt -s nullglob
pool_sources=("$repository_root/debs"/*.deb "$download_dir"/*.deb)
shopt -u nullglob

if ((${#pool_sources[@]} == 0)); then
  echo "No packages available to index." >&2
  exit 65
fi

for package_file in "${pool_sources[@]}"; do
  package_name="$(basename -- "$package_file")"

  if [[ -e "$pool_dir/debs/$package_name" ]]; then
    echo "Duplicate package file name in the pool: $package_name" >&2
    exit 65
  fi

  cp "$package_file" "$pool_dir/debs/$package_name"
done

# Scan the assembled pool and generate every repository index. Running from the
# pool root keeps each package Filename relative (debs/<package>.deb).
(cd "$pool_dir" && apt-ftparchive packages debs) > "$index_dir/Packages"

awk '
  BEGIN {
    RS = ""
    FS = "\n"
  }

  {
    package = ""
    section = ""

    for (field = 1; field <= NF; field++) {
      if ($field ~ /^Package: /) {
        package = substr($field, 10)
      }

      if ($field ~ /^Section: /) {
        section = substr($field, 10)
      }
    }

    if (package != "" && section == "") {
      printf "Package %s is missing the Section field required by Sileo.\n", package > "/dev/stderr"
      exit 1
    }
  }
' "$index_dir/Packages"

xz -9e -c "$index_dir/Packages" > "$index_dir/Packages.xz"

# Keeping Release outside the scanned directory prevents a self-referential hash.
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="OwnGoal Studio" \
  -o APT::FTPArchive::Release::Label="OwnGoal Packages" \
  -o APT::FTPArchive::Release::Suite="stable" \
  -o APT::FTPArchive::Release::Version="1.0" \
  -o APT::FTPArchive::Release::Codename="owngoal" \
  -o APT::FTPArchive::Release::Architectures="iphoneos-arm iphoneos-arm64 iphoneos-arm64e xros-arm64e" \
  -o APT::FTPArchive::Release::Components="main" \
  -o APT::FTPArchive::Release::Description="Official iOS packages from OwnGoal Studio" \
  release "$index_dir" > "$work_dir/Release"

# Assemble the complete Pages artifact only after all metadata has been generated.
cp -R assets "$site_dir/assets"
cp -R "$pool_dir/debs" "$site_dir/debs"
cp CNAME CydiaIcon.png index.html manifest.json "$site_dir/"
cp "$index_dir/Packages" "$index_dir/Packages.xz" "$site_dir/"
cp "$work_dir/Release" "$site_dir/Release"

rm -rf -- "$output_dir"
mv "$site_dir" "$output_dir"

echo "Built APT repository at $output_dir"
