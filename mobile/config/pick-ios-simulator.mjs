import { execSync } from 'node:child_process';
import fs from 'node:fs';

const data = JSON.parse(execSync('xcrun simctl list devices available -j').toString());

let found;
for (const [runtime, devices] of Object.entries(data.devices)) {
    if (!runtime.includes('iOS')) continue;
    const iphone = devices.find((d) => d.name.startsWith('iPhone'));
    if (iphone) {
        found = { name: iphone.name, runtime };
        break;
    }
}

if (!found) {
    console.error('No available iPhone simulator found on this runner.');
    process.exit(1);
}

const match = found.runtime.match(/iOS-(\d+)-(\d+)/);
const platformVersion = match ? `${match[1]}.${match[2]}` : '';
console.log(`Using simulator: ${found.name} / iOS ${platformVersion}`);

const envFile = process.env.GITHUB_ENV;
fs.appendFileSync(envFile, `MOBILE_IOS_DEVICE_NAME=${found.name}\n`);
fs.appendFileSync(envFile, `MOBILE_IOS_PLATFORM_VERSION=${platformVersion}\n`);
