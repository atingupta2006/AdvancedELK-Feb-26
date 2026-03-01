```
sudo yum install epel-release -y && sudo yum install nginx -y
sudo systemctl start nginx
```

```bash
tail -f /var/log/nginx/access.log
```


```bash
# A simple loop to hit the server with different paths
while true; do
  curl -A "Mozilla/5.0" http://localhost/api/products
  curl -A "Mozilla/5.0" http://localhost/api/orders
  curl -A "curl/7.68.0" http://localhost/api/users/12345
  curl -s -o /dev/null http://localhost/non-existent-page  # This generates a 404
  sleep 1
done
```

