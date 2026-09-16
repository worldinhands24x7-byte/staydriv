const { Jimp } = require('jimp');
const path = require('path');

const srcPath = 'C:\\Users\\pc\\.gemini\\antigravity-ide\\brain\\a70a9805-f93d-4088-b046-8a6d93391d43\\media__1783044230679.jpg';
const destBaseDir = 'D:\\New staydriv\\staydriv_app\\android\\app\\src\\main\\res';

const sizes = [
  { name: 'mipmap-mdpi', size: 48 },
  { name: 'mipmap-hdpi', size: 72 },
  { name: 'mipmap-xhdpi', size: 96 },
  { name: 'mipmap-xxhdpi', size: 144 },
  { name: 'mipmap-xxxhdpi', size: 192 }
];

async function generate() {
  try {
    const image = await Jimp.read(srcPath);
    console.log(`Successfully loaded source image: width=${image.bitmap.width}, height=${image.bitmap.height}`);

    for (const target of sizes) {
      const destPath = path.join(destBaseDir, target.name, 'ic_launcher.png');
      
      const cloned = image.clone();

      // We want to fit the vehicle illustration into a square icon.
      // Since it's a wide landscape image, let's contain it inside the target size 
      // with a clean white or transparent background, or crop it, or fit it cleanly.
      // Let's create a solid white background canvas first:
      const container = new Jimp({ width: target.size, height: target.size, color: 0xFFFFFFFF });

      // Scale the cloned image to fit the container width, maintaining aspect ratio
      const newWidth = target.size;
      const newHeight = Math.round(cloned.bitmap.height * (target.size / cloned.bitmap.width));
      cloned.resize({ w: newWidth, h: newHeight });

      // Composite it in the vertical center of the container
      const yOffset = Math.round((target.size - newHeight) / 2);
      container.composite(cloned, 0, yOffset);

      await container.write(destPath);
      console.log(`Generated ${target.name}/ic_launcher.png (${target.size}x${target.size})`);
    }

    console.log("All app launcher icons updated successfully!");
  } catch (err) {
    console.error("Error generating launcher icons:", err);
  }
}

generate();
