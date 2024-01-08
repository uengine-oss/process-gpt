import { createRouter, createWebHashHistory } from 'vue-router';
import CommonStorageBase from "@/components/storage/CommonStorageBase";

const router = createRouter({
    history: createWebHashHistory(),
    routes: [
        {
            path: '/',
            component: () => import('../components/pages/Index.vue'),
        },
        {
            path: '/organization',
            component: () => import('../components/pages/OrganizationChartChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/definitions',
            component: () => import('../components/pages/ProcessManagerChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/definitions/:id',
            component: () => import('../components/pages/ProcessManagerChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/instances',
            component: () => import('../components/pages/ProcessParticipantChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/instances/:id',
            component: () => import('../components/pages/ProcessParticipantChat.vue'),
            meta: {
                requiresAuth: true
            },
        },
        {
            path: '/todolist',
            component: () => import('../components/ui/TodolistGrid.vue'),
            meta: {
                requiresAuth: true
            },
        },
    ],
});

router.beforeEach(async (to, from, next) => {
    const storage = new CommonStorageBase(this);
    await storage.loginUser();    
    
    if (to.matched.some(record => record.meta.requiresAuth)) {
        if (storage.isLogin) {
            next();
        } else {
            alert("로그인 후 이용해주시길 바랍니다.");
            next('/');
        }
    } else {
        next();
    }
});

export default router;
