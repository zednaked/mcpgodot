import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

fs.chmodSync(path.join(__dirname, '..', 'build', 'index.js'), '755');

fs.mkdirSync(path.join(__dirname, '..', 'build', 'scripts'), { recursive: true });
fs.copyFileSync(
  path.join(__dirname, '..', 'src', 'scripts', 'godot_operations.gd'),
  path.join(__dirname, '..', 'build', 'scripts', 'godot_operations.gd')
);

console.log('Build complete');
