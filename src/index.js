/**
 * WordPress dependencies
 */
import { addAction, addFilter } from '@wordpress/hooks';
import {
	doGutenbergNativeSetup,
	initialHtmlGutenberg,
} from '@wordpress/react-native-editor';

/**
 * Internal dependencies
 */
import correctTextFontWeight from './text-font-weight-correct';
import {
	registerJetpackBlocks,
	registerJetpackEmbedVariations,
	setupJetpackEditor,
} from './jetpack-editor-setup';
import setupBlockExperiments from './block-experiments-setup';
import initialHtml from './initial-html';
import initAnalytics from './analytics';
import { getTranslation as getJetpackTranslation } from './i18n-cache/jetpack';
import { getTranslation as getLayoutGridTranslation } from './i18n-cache/layout-grid';

const setupPluginLocale = (
	plugin,
	locale,
	extraTranslations,
	getTranslation
) => {
	const setLocaleData = require( '@wordpress/i18n' ).setLocaleData;

	let translations = getTranslation( locale );
	if ( locale && ! translations ) {
		// Try stripping out the regional
		locale = locale.replace( /[-_][A-Za-z]+$/, '' );
		translations = getTranslation( locale );
	}
	const allTranslations = Object.assign(
		{},
		translations,
		extraTranslations
	);
	// eslint-disable-next-line no-console
	console.log( `${ plugin } locale`, locale, translations );
	if ( allTranslations ) {
		setLocaleData( allTranslations, plugin );
	}
};

addAction( 'native.pre-render', 'gutenberg-mobile', ( props ) => {
	require( './strings-overrides' );
	correctTextFontWeight();

	setupJetpackEditor(
		props.jetpackState || { blogId: 1, isJetpackActive: true }
	);

	// Setup locale for plugins
	setupPluginLocale(
		'jetpack',
		props.locale,
		props.translations,
		getJetpackTranslation
	);
	setupPluginLocale(
		'layout-grid',
		props.locale,
		props.translations,
		getLayoutGridTranslation
	);

	// Jetpack Embed variations use WP hooks that are attached to
	// block type registration, so it’s required to add them before
	// the core blocks are registered.
	registerJetpackEmbedVariations( props );
} );

addAction( 'native.render', 'gutenberg-mobile', ( props ) => {
	const capabilities = props.capabilities ?? {};
	registerJetpackBlocks( props );
	setupBlockExperiments( capabilities );
} );

addFilter( 'native.block_editor_props', 'gutenberg-mobile', ( editorProps ) => {
	if ( __DEV__ ) {
		let { initialTitle, initialData } = editorProps;

		if ( initialTitle === undefined ) {
			initialTitle = 'Welcome to gutenberg for WP Apps!';
		}

		if ( initialData === undefined ) {
			initialData = initialHtml + initialHtmlGutenberg;
		}

		return {
			...editorProps,
			initialTitle,
			initialData,
		};
	}
	return editorProps;
} );

initAnalytics();
doGutenbergNativeSetup();
