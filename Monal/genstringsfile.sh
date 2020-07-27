find Classes/ NotificaionService/ shareSheet-iOS/ -not -path '*/\.*' -type f -name \*.m -print0 | xargs -0 genstrings -o Base.lproj
