const { AceBaseServer } = require("acebase-server");
const { AceBaseClient } = require("acebase-client");

const express = require("express");
const app = express();
const _ = require("lodash");

const dbname = "mydb";
const server = new AceBaseServer(dbname, {
    host: "localhost",
    port: 5757,
    authentication: {
        enabled: true,
        allowUserSignup: true,
        defaultAccessRule: "auth",
        defaultAdminPassword: "75sdDSFg37w5",
    },
});

server.on("ready", () => {
    console.log("SERVER ready");
});

const db = new AceBaseClient({
    host: "localhost",
    port: '5757',
    dbname: "mydb",
    https: false,
});

db.auth.signIn("admin", "75sdDSFg37w5").then((result) => {
    console.log(
        `Signed in as ${result.user.username}, got access token ${result.accessToken}`
    );
});
db.ready(() => {
    console.log("Connected successfully");
});
