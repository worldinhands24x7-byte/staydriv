@echo off
echo ===================================================
echo Packaging StayDriv AWS Elastic Beanstalk Upload Zip
echo ===================================================

powershell -Command "Compress-Archive -Path 'Dockerfile', '.dockerignore', 'server.js', 'package.json', 'package-lock.json', 'public' -DestinationPath 'staydriv-aws-deploy.zip' -Force"

echo.
echo SUCCESS: Generated "staydriv-aws-deploy.zip" inside this folder!
echo You can now upload this ZIP file directly to the AWS Elastic Beanstalk Console.
pause
