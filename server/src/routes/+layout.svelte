<script lang="ts">
	import '../app.css';

	import { AppBar, AppLayout, ThemeInit, ThemeSwitch } from 'svelte-ux';

	let { children } = $props();
</script>

<ThemeInit />

<AppLayout areas="'header header' 'aside main'" navWidth={0}>
	<AppBar title="Motor speed regulator" menuIcon={null}>
		<div slot="actions">
			<ThemeSwitch />
		</div>
	</AppBar>

	<main class="p-4 ">
		{@render children()}
	</main>
</AppLayout>
