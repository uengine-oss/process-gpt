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

const inputInformation = db
    .ref("/definitions/$projectId/information")
    .on("value");
// const changedInformation = db.ref('/definitions/$projectId/information').on('mutate');

inputInformation.subscribe((snapshot) => {
    try {
        console.log("update Information!!");
        const vars = snapshot.ref.vars;

        const projectId = vars.projectId;
        console.log("projectId", projectId);
        const afterInformation = snapshot.val();

        const updateObj = {
            img: afterInformation.img,
            projectName: afterInformation.projectName,
            lastModifiedTimeStamp: afterInformation.lastModifiedTimeStamp,
            createdTimeStamp: afterInformation.createdTimeStamp,
            projectId: projectId,
            authorEmail: afterInformation.authorEmail,
            author: afterInformation.author,
            date: afterInformation.date,
            comment: afterInformation.comment,
            type: afterInformation.type,
        };
        if (afterInformation.permissions) {
            // delete permissions part
            var permissions = {};
            //after
            Object.keys(afterInformation.permissions).forEach((uid) => {
                permissions[uid] = afterInformation.permissions[uid];
            });

            Object.keys(permissions).forEach((uid) => {
                if (permissions[uid]) {
                    db.ref(`userLists/${uid}/share/${projectId}`)
                        .update(updateObj)
                        // .then(function () {
                        //     getCountDefinition.then(function (snapshot) {
                        //         var value = snapshot.val();
                        //         var array = Object.keys(value);
                        //         var count = array.length;
                        //         if (array.indexOf("count") != -1) {
                        //             count = count - 1;
                        //         }
                        //         updateCountDefinition.update(count);
                        //     });
                        // });
                    if (uid === "everyone") {
                        db.ref(
                            `userLists/${uid}/share_${afterInformation.type}/${projectId}`
                        ).update(updateObj);
                        db.ref(
                            `userLists/${uid}/share_first/${projectId}`
                        ).update(updateObj);
                    }
                } else {
                    db.ref(`userLists/${uid}/share/${projectId}`).remove();
                    if (uid === "everyone") {
                        // getCountDefinition.then(function (snapshot) {
                        //     var value = snapshot.val();
                        //     var array = Object.keys(value);
                        //     var count = array.length;
                        //     if (array.indexOf("count") != -1) {
                        //         count = count - 1;
                        //     }
                        //     updateCountDefinition.update(count);
                        // });
                        db.ref(
                            `userLists/${uid}/share_${beforeInformation.type}/${projectId}`
                        ).remove();
                        db.ref(
                            `userLists/${uid}/share_first/${projectId}`
                        ).remove();
                    }
                }
            });
        }
        // TODO: 1번
        if (updateObj.author) {
            db.ref(`userLists/${updateObj.author}/mine/${projectId}`).update(
                updateObj
            );
        }
    } catch (e) {}
});

// exports.onRegisterUser
db.ref("__auth__/accounts/$uid").on("value").subscribe(async (snapshot, context) => {
    var uid = snapshot.ref.vars.uid;
    var userItem = snapshot.val();
    var userEmail = userItem.email;

    try {
        var convertEmail = userEmail.replace(/\./gi, "_");
        var getInvitationItem = null;
        var getRecommendedUserCoin = null;
        var updates = {};
        userItem["uid"] = uid;
        //invited 파악.
        db.ref(`enrolledUsers/${convertEmail}`).set(userItem);
    } catch (e) {
        return false;
    }
});

db.ref("/definitions/$projectId/information").on('mutated',
    snap => {
        try {
            var projectId = snap.ref.vars.projectId;
            const beforeInformation = snap.val();
            const afterInformation = snap.val();
            if (beforeInformation) {
                if (afterInformation) {
                    // modify
                    var updateObj = {
                        img: afterInformation.img,
                        projectName: afterInformation.projectName,
                        lastModifiedTimeStamp: afterInformation.lastModifiedTimeStamp,
                        createdTimeStamp: afterInformation.createdTimeStamp,
                        projectId: projectId,
                        authorEmail: afterInformation.authorEmail,
                        author: afterInformation.author,
                        date: afterInformation.date,
                        comment: afterInformation.comment,
                        type: afterInformation.type,
                    };
                    
                    var updateMineObj = {
                        author: afterInformation.author,
                        authorEmail: afterInformation.authorEmail,
                        img: afterInformation.img,
                        projectName: afterInformation.projectName,
                        lastModifiedTimeStamp: afterInformation.lastModifiedTimeStamp,
                        createdTimeStamp: afterInformation.createdTimeStamp,
                        projectId: projectId,
                        comment: afterInformation.comment,
                        type: afterInformation.type
                    };
                    //mine update
                    // 2번
                    if(afterInformation.author == undefined) {
                        console.log("*********************************************")
                        console.log(updateObj.author)
                        console.log("*********************************************")    
                    }
                    if(afterInformation.author) {
                        db.ref(
                            `userLists/${afterInformation.author}/mine/${projectId}/information`
                        )
                        .update(updateMineObj);
                    }
                    

                    if (afterInformation.permissions) {
                        // delete permissions part

                        var permissions = {};

                        if (beforeInformation.permissions) {
                            Object.keys(beforeInformation.permissions).forEach(
                                (uid) => {
                                    permissions[uid] = null;
                                }
                            );

                            // Object.keys(beforeInformation.permissions).forEach(function (uid) {
                            //     permissions[uid] = null
                            // })
                        }

                        Object.keys(afterInformation.permissions).forEach(
                            (uid) => {
                                permissions[uid] =
                                    afterInformation.permissions[uid];
                            }
                        );
                        // Object.keys(afterInformation.permissions).forEach(function (uid) {
                        //     permissions[uid] = afterInformation.permissions[uid]
                        // })

                        Object.keys(permissions).forEach((uid) => {
                            if (permissions[uid]) {
                                snap.after.ref.root
                                    .child(
                                        `userLists/${uid}/share/${projectId}`
                                    )
                                    .update(updateObj);
                                if (uid === "everyone") {
                                    db.ref(
                                            `userLists/${uid}/share_${afterInformation.type}/${projectId}`
                                        )
                                        .update(updateObj);
                                }
                            } else {
                                db.ref(
                                        `userLists/${uid}/share/${projectId}`
                                    )
                                    .remove();
                                if (uid === "everyone") {
                                    db.ref(
                                            `userLists/${uid}/share_${beforeInformation.type}/${projectId}`
                                        )
                                        .remove();
                                }
                            }
                        });
                    } else if (beforeInformation.permissions) {
                        // delete permissions all

                        Object.keys(beforeInformation.permissions).forEach(
                            (uid) => {
                                if (uid) {
                                    db.ref(
                                            `userLists/${uid}/share/${projectId}`
                                        )
                                        .remove();
                                    if (uid === "everyone") {
                                        db.ref(
                                                `userLists/${uid}/share_${beforeInformation.type}/${projectId}`
                                            )
                                            .remove();
                                    }
                                }
                            }
                        );
                    }
                }
                return true;
            } else {
                return true;
            }
        } catch (e) {
            console.log(e);
        }
    }
);

const deleteDefinition = db.ref("/userLists/$uid/mine/$projectId").on("value");
deleteDefinition.subscribe((snapshot) => {
    try {
        if (snapshot.val() == null) {
            const vars = snapshot.ref.vars;
            var userUid = vars.uid;
            var projectId = vars.projectId;
            console.log(userUid, projectId);
            db.ref(`definitions/${projectId}/information/permissions`).once(
                "value",
                (permissionsSnapshots) => {
                    if (permissionsSnapshots.exists()) {
                        var userList = permissionsSnapshots.val();
                        Object.keys(userList).forEach((uid) => {
                            if (userList[uid] && uid !== "everyone") {
                                db.ref(
                                    `userLists/${uid}/share/${projectId}`
                                ).update({ state: "deleted" });
                            }
                        });
                    }
                }
            );
            //public delete
            // db.ref(`userLists/everyone/share/${projectId}`)
            //     .remove()
            //     .then(function () {
            //         getCountDefinition.then(function (snapshot) {
            //             var value = snapshot.val();
            //             var array = Object.keys(value);
            //             var count = array.length;
            //             if (array.indexOf("count") != -1) {
            //                 count = count - 1;
            //             }
            //             updateCountDefinition.update(count);
            //         });
            //     });
            db.ref(`userLists/everyone/share_es/${projectId}`)
                .remove()
                .then(function () {});
            db.ref(`userLists/everyone/share_first/${projectId}`)
                .remove()
                .then(function () {});
            return;
        }
    } catch (e) {
        console.log("/userLists/$uid/mine/$projectId");
        console.log(e);
    }
});

db.ref("/userLists/$authorId/mine").on("child_removed", (snapshot) => {
    // console.log("remove!!!!!!!!!!!")
    const vars = snapshot.val();
    console.log(vars.projectId)
    db.ref(`/definitions/${vars.projectId}`).remove()
})

db.ref("/userLists/$authorId/mine").on("child_added", (snapshot) => {
    // console.log("remove!!!!!!!!!!!")
    const vars = snapshot.val();
    console.log(vars.projectId)
    db.ref(`/definitions/${vars.projectId}/information`).update(vars)
})

app.get("/api/definitions/:definition", async function (req, res, next) {
    const snapshot = await db.ref(`definitions/${req.params.definition}`).get();
    if (snapshot.exists()) {
        const tmp = snapshot.val();
        const lastVersion = tmp.information.lastVersionName;
        console.log(tmp.versionLists[lastVersion].versionValue.value);
        const lastValue = JSON.parse(
            tmp.versionLists[lastVersion].versionValue.value
        );
        console.log(lastVersion);
        const result = await bpmParser(req.params.definition, lastValue);
        res.status(200).json(result);
        console.log(result);
    } else {
        res.status(500);
    }
});


const application = app.listen(5758, () => {
    console.log("server open");
});

process.on("SIGTERM", shutDown);
process.on("SIGINT", shutDown);
function shutDown() {
    console.log("Received kill signal, shutting down gracefully");
    application.close(() => {
        console.log("Closed out remaining connections");
        process.exit(0);
    });

    setTimeout(() => {
        console.error(
            "Could not close connections in time, forcefully shutting down"
        );
        process.exit(1);
    }, 10000);

    // connections.forEach(curr => curr.end());
    // setTimeout(() => connections.forEach(curr => curr.destroy()), 5000);
}