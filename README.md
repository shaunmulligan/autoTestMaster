## Resin Sync Base Image
This base image allows you to sync a folder on your host machine to a resin.io device.

To get started, first install the resin CLI and the additional sync plugin
```
sudo npm install -g resin-cli resin-plugin-sync
```
To check that the sync plugin is activated correctly, run the following command:
```
resin help sync
```

Next we need to push this repo (i.e resin-sync-device-side) to our device. We also need to set up an environment variable on the [dashboard](https://dashboard.resin.io/):
`TOKEN` = `<your_resin_token>`
You can get this Token from your preferences page.

You will also need to enable the [resin device URL](http://docs.resin.io/#/pages/runtime/runtime.md), this can be done from the Actions page on the device's dashboard.

Once the device has pulled the code you can just run this sync command which will sync your `/src` directory in this repo to your `/usr/src/app` directory on the device:
```
resin sync <RESIN_DEVICE_UUID> --watch --delay 4000 --source /src
```
replacing <RESIN_DEVICE_UUID> with the UUID of your resin.io device. The `--watch` option allows the sync to keep running and watching the files in `/src` the `--delay` option is the number of milliseconds that resin sync will wait in between successive saves.

Now any time you save any of the files in the `/src` directory they will automatically be synced to the device and the container will be restarted. It should only take about 20 seconds to have the new code running. You can of course sync the whole repo, but bare in mind that this will then sync the whole repo to `/usr/src/app` so you will need to change your dockerfile accordingly.

Obviously if you need to install any dependencies or pip install stuff, you will need to add them to the Dockerfile or requirements.txt file and do a full `git push resin master`

Another nice side affect of this base image is that you can ssh into the container using:
```
ssh root@<MY_DEVICE_IP> -p80
```
and the passphrase is `resin`
