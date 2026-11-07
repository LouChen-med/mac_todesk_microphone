-- Invoked by install-blackhole.sh after staging and package checks.
-- All authentication happens in the native macOS administrator dialog.
on run argv
    if (count of argv) is not 1 then error "需要一个已校验并暂存的 BlackHole 2ch PKG 路径。"
    set packagePath to item 1 of argv
    set quotedPackage to quoted form of packagePath
    -- Check the official installer identity again inside the privileged operation.
    set verifyCommand to "signature=$(/usr/bin/env LC_ALL=C /usr/sbin/pkgutil --check-signature " & quotedPackage & ") && case \"$signature\" in *'Developer ID Installer: Existential Audio Inc. (Q5C99V536K)'*) ;; *) /bin/echo 'Official installer signature mismatch' >&2; exit 1 ;; esac"
    set installCommand to verifyCommand & " && /usr/sbin/spctl --assess --type install " & quotedPackage & " && /usr/sbin/installer -pkg " & quotedPackage & " -target / && /usr/bin/killall -TERM coreaudiod"
    return do shell script installCommand with administrator privileges with prompt "安装官方 BlackHole 2ch 虚拟麦克风并刷新音频服务。Mac 不会重启。"
end run
