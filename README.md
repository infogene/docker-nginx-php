# Docker image, for php web-based apps, from php DOCKER OFFICIAL IMAGE

## Maintained by: [Infogene](https://infogene.fr)

This is the Git repo of the [Docker Image](https://github.com/infogene/docker-nginx-php) for [`nginx-php`](https://github.com/infogene/docker-nginx-php/pkgs/container/nginx-php) (not to be confused with any official `php` image provided by `php` upstream). See [the Docker Hub page](https://hub.docker.com/_/php/) for the full readme on how to use the PHP Official Docker image.

# Quick startup

```shell
docker run -d --name my-webapp -p 8080:80 ghcr.io/infogene/nginx-php:latest
```

This will start un new docker container running in background, and mapping host-port 8080 to container-port 80.
To see what this container launch, visit http://localhost:8080 (Or http://<your-host-docker>:8080)

You will see the default output of the `phpinfo()` function. 

# How to use

#### Mount your Php Web-Application as volume
```shell
docker run -d --name my-webapp -p 8080:80 -v$PWD:/application ghcr.io/infogene/nginx-php:latest
```

#### Create your own Dockerfile

> Build your image from `ghcr.io/infogene/nginx-php:latest`
> 
> `$APP_DIR` is a simple variable that contain the default path of the application, default value is: `/application`
```dockerfile
FROM ghcr.io/infogene/nginx-php:latest

COPY COPY --chown=www-data:www-data ./ $APP_DIR
```

---

> Customization : You can customize your image, in the same way as the docker php official image, by using `docker-php-ext-configure` and `docker-php-ext-install`
```dockerfile
FROM ghcr.io/infogene/nginx-php:latest

RUN apt-get update && apt-get install -y \
		libfreetype6-dev \
		libjpeg62-turbo-dev \
		libpng-dev \
	&& docker-php-ext-configure gd --with-freetype --with-jpeg \
	&& docker-php-ext-install -j$(nproc) gd
```

#### Customize at startup

> Customization : Use option --mode-dev (default --mode-prod), will enable by default xdebug and output nginx access/error logs
```shell
docker run -d --name my-webapp -p 8080:80 -v$PWD:/application ghcr.io/infogene/nginx-php:latest --mode-dev
```
---
> Customization : Use option --mode-cron, will run your configured crontab
> 
> PHP-FPM and nginx will not be started in `cron mode`
```shell
docker run -d --name my-webapp -v$PWD:/application -v$PWD/mycrontab:/var/spool/cron/crontabs/mycrontab ghcr.io/infogene/nginx-php:latest --mode-cron
```
---
> Customization : Provide your own command, will run any `shell` command
>
> PHP-FPM and nginx will not be started in `cron mode`
```shell
docker run --name my-webapp -v$PWD:/application ghcr.io/infogene/nginx-php:latest ls -l
```

---
> Use Env Variables : 
>
> `APP_BOOT_PERMS_FLUSH=true|false` : if true, files permissions will be adjusted: 775 and group www-data  
> 
> `APP_BOOT_CMD=<any shell cmd>` : if provided, the `cmd` will be executed at startup
>
> `APP_BOOT_PHP_XDEBUG_ENABLED=true|false` : if true, xdebug extension will be enabled
>
> `APP_BOOT_PHP_EXT_ENABLED=<list of php modules>` : if provided, the list of php modules will be enabled

```shell
docker run --name my-webapp -v$PWD:/application ghcr.io/infogene/nginx-php:latest ls -l
```
