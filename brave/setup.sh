#!/bin/bash

[[ -e setup.sh  ]] || { echo 'setup.sh must be run from brave directory'; exit 1; }

# Pro Tip for ad-hoc building: add your app id as an arg, like ./setup.sh org.foo.myapp

app_id=${1:-`whoami`.brave}
echo Using APPID of $app_id, you can customize using ./setup.sh org.foo.myapp

echo CUSTOM_BUNDLE_ID=$app_id > xcconfig/local-def.xcconfig
# Custom IDs get the BETA property set automatically
[[ $app_id != com.brave.ios.browser ]] && echo BETA=Beta >> xcconfig/local-def.xcconfig

sed -e "s/APPGROUP_PLACEHOLDER/group.$app_id/" Brave.entitlements.template > Brave.entitlements

# if a brave build, setup configurations
if [[ $app_id == com.brave.ios.browser* ]]; then
    dev_team_id="KL8N8XSYF4"
    sed -i '' -e "s/KEYCHAIN_PLACEHOLDER/$dev_team_id.$app_id/" Brave.entitlements
    echo "DEVELOPMENT_TEAM=$dev_team_id" >> xcconfig/local-def.xcconfig

    # using comma delimiter to escape forward slashes properly
    sed -e s,https://laptop-updates-staging.herokuapp.com,$(head -1 ~/.brave-urp-host-key), BraveInfo.plist.template |
    sed -e s,\<string\>key\</string\>,\<string\>$(head -1 ~/.brave-api-key)\</string\>, > BraveInfo.plist
else
    sed -i '' -e "s/KEYCHAIN_PLACEHOLDER/\$\(AppIdentifierPrefix\)$app_id/" Brave.entitlements
    cat BraveInfo.plist.template > BraveInfo.plist
    echo "Please edit xcconfig/local-def.xcconfig to add your DEVELOPMENT_TEAM id (or else you will need to set this in Xcode)"
    echo "  It is found here: https://developer.apple.com/account/#/membership"
    echo "// DEVELOPMENT_TEAM=" >> xcconfig/local-def.xcconfig
fi

echo GENERATED_BUILD_ID=`date +"%y.%m.%d.%H"` >> xcconfig/build-id.xcconfig

npm update

# setup adblock regional filters
if ! g++ build-system/get_adblock_regions.cpp -Inode_modules/ad-block/ -std=c++11 -o get_adblock_regions; then
    echo "Error: could not setup adblock region file."
    exit 1
fi

./get_adblock_regions && rm get_adblock_regions

if [ ! -e adblock-regions.txt ]; then
    echo "Error: adblock region file does not exist."
    exit 1
fi

## setup sync
(cd ../Carthage/Checkouts/sync && brew install yarn; yarn install && yarn run build)

# setup brave/crypto
(cd ../Carthage/Checkouts/crypto && brew install yarn; yarn install && yarn run build)
