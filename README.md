# windows-ec2-starter

A small script to automatically handle the details of starting and stopping a Windows desktop on EC2 for a specified time period (say, a few hours).
The AWS-generated RDP password is automatically retrieved from AWS, decrypted, and displayed after AWS is finished starting the instance.

##### dependencies

    Paws::EC2
    DateTime
    MIME::Base64
