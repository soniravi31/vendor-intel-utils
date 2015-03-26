# save the official lunch command to aosp_lunch() and source it
tmp_lunch=`mktemp`
sed '/ lunch()/,/^}/!d'  build/envsetup.sh | sed 's/function lunch/function aosp_lunch/' > ${tmp_lunch}
source ${tmp_lunch}
rm ${tmp_lunch}

function get_aosp_type
{
    local cmn_path="device/intel/common/select_aosp"
    local target_list="${cmn_path}/target_list.txt"

    while read -r line
    do
        echo "${TARGET_PRODUCT}" | grep -q "${line}" && echo "vanilla" && return
    done < "${target_list}"

    echo "legacy"
}

# Override lunch function to apply patches on AOSP
function lunch
{
    local aosp_type

    previous_aosp_type=$(get_aosp_type)
    aosp_lunch $*

    # return an error if aosp lunch return an error
    if [ "$?" -ne "0" ]; then
        return 1
    fi

    local cmn_path="device/intel/common/select_aosp"

    aosp_type=$(get_aosp_type)
    echo AOSP_TYPE is $aosp_type

    # In case script does not execute to the end - create show stopper
    (\cp ${cmn_path}/Show-stopper.mk ${cmn_path}/Android.mk)

    if [ "${aosp_type}" == "vanilla" ]; then
        (\repo forall -g aosp -c 'echo "$REPO_PROJECT $REPO_PATH"' | xargs -P 5 -L 1 bash -c 'cd "$1" && pwd && git fetch --no-tags ssh://android.intel.com/"$0" +platform/android/vanilla_imin_legacy:remotes/umg/platform/android/vanilla_imin_legacy && git checkout remotes/umg/platform/android/vanilla_imin_legacy' || (t=$? ; echo "cannot setup environment"; echo "failed" > lunch_failed.txt; exit $t))

        # Generate specific manifest for Nexus devices
        (\mkdir pub)
        (\repo manifest -r -o pub/manifest-generated-nexus.xml)
        (\sed -i 's/.*vendor\/intel\/PRIVATE\/utils.*//g' pub/manifest-generated-nexus.xml)
    fi

    if [ "${previous_aosp_type}" == "vanilla" ] && [ "${aosp_type}" == "legacy" ]; then
        echo "*********************************************************************"
        echo "** WARNING : Switching from vanilla aosp to legacy aosp            **"
        echo "**           Syncing AOSP from imin_legacy                         **"
        echo "*********************************************************************"
        repo init -m android-imin_legacy
        repo sync -c -j5 -l $(repo forall -g aosp -c 'echo "$REPO_PATH "')
    fi

    # All went well, disable the show-stopper Makefile
    (\rm -f ${cmn_path}/Android.mk)
}
