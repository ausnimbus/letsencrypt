package main

import (
  "os"
  "fmt"
  "time"
  "net/http"
  "strings"
  "path/filepath"
  "github.com/gorhill/cronexpr"
)

func renew(renewCronExpr *cronexpr.Expression) {

  for {
    now := time.Now()
    next := renewCronExpr.Next(now)
    fmt.Printf("Next certificate renewal run at %v\n", next)
    time.Sleep(next.Sub(now))

    certs, _ := filepath.Glob("/var/lib/letsencrypt/*.crt")
    for _, cert := range certs {
      domain :=  strings.TrimSuffix(filepath.Base(cert), filepath.Ext(cert))
      proc := sh("/usr/local/letsencrypt/bin/letsencrypt.sh '%s' `cat /run/secrets/kubernetes.io/serviceaccount/token`", domain)
      fmt.Println(proc.stderr + proc.stdout)
    }
  }
}

func handler(w http.ResponseWriter, r *http.Request) {
  if r.Header["Authorization"] == nil || r.Header["Domain"] == nil {
    // Set the HTTP status code to 403
    w.WriteHeader(http.StatusForbidden)
    w.Write([]byte("Unauthorized "))
  } else {
    proc := sh("/usr/local/letsencrypt/bin/letsencrypt.sh '%s' '%s'", r.Header["Domain"][0], strings.Split(r.Header["Authorization"][0], " ")[1])
    fmt.Fprintln(w,proc.stderr + proc.stdout)
  }
}

func main() {
  renewCron := os.Getenv("RENEW_CRON")
  if renewCron == "" {
    renewCron = "@daily"
  }

  renewCronExpr := cronexpr.MustParse(renewCron)
  if renewCronExpr.Next(time.Now()).IsZero() {
    panic("Cron expression doesn't match any future dates!")
  }

  go renew(renewCronExpr)

  http.HandleFunc("/", handler)
  http.Handle("/.well-known/acme-challenge/", http.FileServer(http.Dir("/srv")))
  http.ListenAndServe(":8080", nil)
}
